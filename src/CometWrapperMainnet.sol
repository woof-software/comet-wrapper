// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { CometInterface } from "./vendor/CometInterface.sol";
import { CometHelpers } from "./CometHelpers.sol";
import { ICometRewardsMainnet } from "./vendor/ICometRewardsMainnet.sol";
import {
    ERC4626Upgradeable,
    ERC20Upgradeable as ERC20,
    IERC20Upgradeable as IERC20,
    IERC20MetadataUpgradeable as IERC20Metadata
} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ECDSA } from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import { IERC1271 } from "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";

/**
 * @title Comet Wrapper
 * @notice Wrapper contract that adds ERC4626 functionality to the rebasing Comet token (e.g. cUSDCv3)
 * @author Compound & gjaldon
 */
contract CometWrapperMainnet is ERC4626Upgradeable, CometHelpers {
    using SafeERC20Upgradeable for IERC20;

    struct UserBasicTracking {
        uint64 baseTrackingAccrued;
        uint64 baseTrackingIndex;
    }

    /// @notice The major version of this contract
    string public constant VERSION = "1";

    /// @dev The EIP-712 typehash for authorization via permit
    bytes32 internal constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 amount,uint256 nonce,uint256 deadline)");

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @dev The magic value that a contract's `isValidSignature(bytes32 hash, bytes signature)` function should
    ///  return for a valid signature
    ///  See https://eips.ethereum.org/EIPS/eip-1271
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice Mapping of users to basic data
    mapping(address user => UserBasicTracking basicTrackingData) public userBasic;

    /// @notice Mapping of users to their rewards claimed
    mapping(address owner => uint256 amount) public rewardsClaimed;

    /// @notice The next expected nonce for an address, for validating authorizations via signature
    mapping(address sender => uint256 nonce) public nonces;

    /// @notice The Comet address that this contract wraps
    CometInterface public immutable comet;

    /// @notice The CometRewards address that this contract can claim rewards from
    ICometRewardsMainnet public immutable cometRewards;

    /// @notice The scale for reward tracking
    uint256 public immutable trackingIndexScale;

    /// @notice Factor to divide by when accruing rewards in order to preserve 6 decimals (i.e. baseScale / 1e6)
    uint256 internal immutable accrualDescaleFactor;

    /** Custom errors **/

    error BadSignatory();
    error BadRewards();
    error EIP1271VerificationFailed();
    error InsufficientAllowance();
    error InsufficientAvailableBalance();
    error InvalidSignatureS();
    error SignatureExpired();
    error TimestampTooLarge();
    error UninitializedReward();
    error Unauthorized();
    error ZeroShares();

    /** Custom events **/

    /// @notice Event emitted when a reward is claimed for a user
    event RewardClaimed(address indexed src, address indexed recipient, address indexed token, uint256 amount);

    /**
     * @notice Construct a new Comet Wrapper instance
     * @dev Disables initialization on the implementation contract
     * @param comet_ The Comet token to wrap
     * @param cometRewards_ The rewards contract for the Comet market
     */
    constructor(CometInterface comet_, ICometRewardsMainnet cometRewards_) {
        // Minimal validation that contract is CometRewards
        if(cometRewards_.rewardConfig(address(comet_)).token == address(0)) revert BadRewards();

        comet = comet_;
        cometRewards = cometRewards_;
        trackingIndexScale = comet.trackingIndexScale();
        accrualDescaleFactor = uint64(10 ** IERC20Metadata(address(comet_)).decimals()) / BASE_ACCRUAL_SCALE;

        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param name_ The wrapper token name
     * @param symbol_ The wrapper token symbol
     */
    function initialize(string calldata name_, string calldata symbol_) initializer public {
        __ERC4626_init(IERC20(address(comet)));
        __ERC20_init(name_, symbol_);
    }

    /**
     * @notice Returns total assets managed by the vault
     * @return total assets
     */
    function totalAssets() public view override returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        uint256 supply = totalSupply();
        return supply > 0 ? presentValueSupply(baseSupplyIndex_, supply, Rounding.DOWN) : 0;
    }

    /**
     * @notice Deposits assets into the vault and gets shares (Wrapped Comet token) in return
     * @param assets The amount of assets to be deposited by the caller
     * @param receiver The recipient address of the minted shares
     * @return The amount of shares that are minted to the receiver
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (assets == type(uint256).max) assets = IERC20(asset()).balanceOf(msg.sender);
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        accrueInternal(receiver);
        uint256 shares = previewDeposit(assets);
        if (shares == 0) revert ZeroShares();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    /**
     * @notice Mints shares (Wrapped Comet) in exchange for Comet tokens
     * @param shares The amount of shares to be minted for the receive
     * @param receiver The recipient address of the minted shares
     * @return The amount of assets that are deposited by the caller
     */
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        if (shares == 0) revert ZeroShares();

        accrueInternal(receiver);
        uint256 assets = previewMint(shares);

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    /**
     * @notice Withdraws assets (Comet) from the vault and burns corresponding shares (Wrapped Comet).
     * Caller can only withdraw assets from owner if they have been given allowance to.
     * @param assets The amount of assets to be withdrawn by the caller
     * @param receiver The recipient address of the withdrawn assets
     * @param owner The owner of the assets to be withdrawn
     * @return The amount of shares of the owner that are burned
     */
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        accrueInternal(owner);
        uint256 shares = previewWithdraw(assets);
        if (shares == 0) revert ZeroShares();

        if(owner != msg.sender) _spendAllowance(owner, msg.sender, shares);

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @notice Redeems shares (Wrapped Comet) in exchange for assets (cTokens).
     * Caller can only redeem shares from owner if they have been given allowance to.
     * @param shares The amount of shares to be redeemed
     * @param receiver The recipient address of the withdrawn assets
     * @param owner The owner of the shares to be redeemed
     * @return The amount of assets that is withdrawn and sent to the receiver
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        if (shares == 0) revert ZeroShares();

        accrueInternal(owner);
        uint256 assets = previewRedeem(shares);

        if(owner != msg.sender) _spendAllowance(owner, msg.sender, shares);

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @notice Transfer shares from caller to the recipient
     * @dev Confirms the available balance of the caller is sufficient to cover transfer
     * @param to The receiver of the shares to be transferred
     * @param amount The amount of shares to be transferred
     * @return bool Indicates success of the transfer
     */
    function transfer(address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        transferInternal(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Transfer shares from a specified source to a recipient
     * @param from The source of the shares to be transferred
     * @param to The receiver of the shares to be transferred
     * @param amount The amount of shares to be transferred
     * @return bool Indicates success of the transfer
     */
    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        if(from != msg.sender)  _spendAllowance(from, msg.sender, amount);
        transferInternal(from, to, amount);
        return true;
    }

    /**
     * @dev Update the balances of the addresses involved in a token transfer. Before the balances are updated,
     * interest is first accrued and tracking indices are updated.
     */
    function transferInternal(address from, address to, uint256 amount) internal {
        // Accrue rewards before transferring assets
        comet.accrueAccount(address(this));
        updateTrackingIndex(from);
        updateTrackingIndex(to);

        _transfer(from, to, amount);
    }

    /**
     * @notice Total assets of an account that are managed by this vault
     * @dev The asset balance is computed from an account's shares balance which mirrors how Comet
     * computes token balances. This is done this way since balances are ever-increasing due to
     * interest accrual.
     * @param account The address to be queried
     * @return The total amount of assets held by an account
     */
    function underlyingBalance(address account) public view returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        uint256 principal = balanceOf(account);
        return principal > 0 ? presentValueSupply(baseSupplyIndex_, principal, Rounding.DOWN) : 0;
    }

    /**
     * @dev Updates an account's `baseTrackingAccrued` which keeps track of rewards accrued by the account.
     * This uses the latest `trackingSupplyIndex` from Comet to compute for rewards accrual for accounts
     * that supply the base asset to Comet.
     */
    function updateTrackingIndex(address account) internal {
        UserBasicTracking memory basic = userBasic[account];
        uint256 principal = balanceOf(account);
        (, uint64 trackingSupplyIndex,) = getSupplyIndices();

        if (principal > 0) {
            uint256 indexDelta = uint256(trackingSupplyIndex - basic.baseTrackingIndex);
            basic.baseTrackingAccrued +=
                safe64(principal * indexDelta / trackingIndexScale / accrualDescaleFactor);
        }
        basic.baseTrackingIndex = trackingSupplyIndex;
        userBasic[account] = basic;
    }

    /**
     * @dev Update the interest accrued to the wrapper and the tracking index for an account
     */
    function accrueInternal(address account) internal {
        comet.accrueAccount(address(this));
        updateTrackingIndex(account);
    }

    /**
     * @notice Get the reward owed to an account
     * @dev This is designed to exactly match computation of rewards in Comet
     * and uses the same configuration as CometRewards. It is a combination of both
     * [`getRewardOwed`](https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/CometRewards.sol#L110)
     * and [`getRewardAccrued`](https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/CometRewards.sol#L171).
     * @param account The address to be queried
     * @param shouldAccrue Whether to accrue rewards before claiming
     * @return The total amount of rewards owed to an account
     */
    function getRewardOwed(address account, bool shouldAccrue) external returns (uint256) {
        ICometRewardsMainnet.RewardConfig memory config = cometRewards.rewardConfig(address(comet));
        return getRewardOwedInternal(config, account, shouldAccrue);
    }

    /**
     * @dev Mimics the reward owed calculation in CometRewards to arrive at the reward owed to a user of the wrapper
     */
    function getRewardOwedInternal(ICometRewardsMainnet.RewardConfig memory config, address account, bool shouldAccrue) internal returns (uint256 owed) {
        if (config.token == address(0)) revert UninitializedReward();

        UserBasicTracking memory basic = accrueRewards(account, shouldAccrue);
        uint256 claimed = rewardsClaimed[account];
        uint256 accrued = basic.baseTrackingAccrued;

        // Note: Newer CometRewards contracts (those deployed on L2s) store a multiplier and use it during the reward calculation.
        // As of 10/05/2023, all the multipliers are currently set to 1e18, so the following code is still compatible. This contract
        // will need to properly handle the multiplier if there is ever a rewards contract that sets it to some other value.
        if (config.shouldUpscale) {
            accrued *= config.rescaleFactor;
        } else {
            accrued /= config.rescaleFactor;
        }

        owed = accrued > claimed ? accrued - claimed : 0;

        return owed;
    }

    /**
     * @notice Claims caller's rewards and sends them to recipient
     * @dev Always calls CometRewards for updated configs
     * @param to The address that will receive the rewards
     * @param shouldAccrue Whether to accrue rewards before claiming
     */
    function claimTo(address to, bool shouldAccrue) external {
        address from = msg.sender;
        ICometRewardsMainnet.RewardConfig memory config = cometRewards.rewardConfig(address(comet));
        uint256 owed = getRewardOwedInternal(config, from, shouldAccrue);

        if (owed != 0) {
            rewardsClaimed[from] += owed;
            cometRewards.claimTo(address(comet), address(this), address(this), true);
            IERC20(config.token).safeTransfer(to, owed);
            emit RewardClaimed(from, to, config.token, owed);
        }
    }

    /**
     * @notice Accrues rewards for the account
     * @dev Latest trackingSupplyIndex is fetched from Comet so we can compute accurate rewards.
     * This mirrors the logic for rewards accrual in CometRewards so we properly account for users'
     * rewards as if they had used Comet directly.
     * @param account The address to whose rewards we want to accrue
     * @param shouldAccrue Whether to accrue rewards before claiming
     * @return The UserBasic struct with updated baseTrackingIndex and/or baseTrackingAccrued fields
     */
    function accrueRewards(address account, bool shouldAccrue) public returns (UserBasicTracking memory) {
        if(shouldAccrue) comet.accrueAccount(address(this));
        updateTrackingIndex(account);
        return userBasic[account];
    }

    /**
     * @dev This returns latest baseSupplyIndex regardless of whether comet.accrueAccount has been called for the
     * current block. This works like `Comet.accruedInterestIndices` at but not including computation of
     * `baseBorrowIndex` since we do not need that index in CometWrapper:
     * https://github.com/compound-finance/comet/blob/63e98e5d231ef50c755a9489eb346a561fc7663c/contracts/Comet.sol#L383-L394
     */
    function accruedSupplyIndex() internal view returns (uint64) {
        (uint64 baseSupplyIndex_,,uint40 lastAccrualTime) = getSupplyIndices();
        uint256 timeElapsed = uint256(getNowInternal() - lastAccrualTime);
        if (timeElapsed > 0) {
            uint256 utilization = comet.getUtilization();
            uint256 supplyRate = comet.getSupplyRate(utilization);
            baseSupplyIndex_ += safe64(mulFactor(baseSupplyIndex_, supplyRate * timeElapsed));
        }
        return baseSupplyIndex_;
    }

    /**
     * @dev To maintain accuracy, we fetch `baseSupplyIndex` and `trackingSupplyIndex` directly from Comet.
     * baseSupplyIndex is used on the principal to get the user's latest balance including interest accruals.
     * trackingSupplyIndex is used to compute for rewards accruals.
     */
    function getSupplyIndices() internal view returns (uint64, uint64, uint40) {
        CometInterface.TotalsBasic memory totals = comet.totalsBasic();
        return (totals.baseSupplyIndex, totals.trackingSupplyIndex, totals.lastAccrualTime);
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view override returns (uint256) {
        if(comet.isTransferPaused()) return 0;
        return uint256(type(uint104).max);
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view override returns (uint256) {
        if(comet.isTransferPaused()) return 0;
        return uint256(type(uint104).max);
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view override returns (uint256) {
        if(comet.isTransferPaused()) return 0;
        return balanceOf(owner);
    }

    /**
     * @notice Sets Comet's ERC20 allowance of an asset for a manager
     * @dev Only callable by governor
     * @dev Note: Setting the `asset` as Comet's address will allow the manager
     * to withdraw from Comet's Comet balance
     * @param asset The asset that the manager will gain approval of
     * @param manager The account which will be allowed or disallowed
     * @param amount The amount of an asset to approve
     */
    function approveThis(address manager, address asset, uint amount) external {
        if (msg.sender != comet.governor()) revert Unauthorized();

        ERC20(asset).approve(manager, amount);
    }

    /**
     * @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     * @dev Treats shares as principal and computes for assets by taking into account interest accrual. Relies on latest
     * `baseSupplyIndex` from Comet which is the global index used for interest accrual the from supply rate.
     * @param shares The amount of shares to be converted to assets
     * @return The total amount of assets computed from the given shares
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        return shares > 0 ? presentValueSupply(baseSupplyIndex_, shares, Rounding.DOWN) : 0;
    }

    /**
     * @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     * @dev Assets are converted to shares by computing for the principal using the latest `baseSupplyIndex` from Comet.
     * @param assets The amount of assets to be converted to shares
     * @return The total amount of shares computed from the given assets
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        return assets > 0 ? principalValueSupply(baseSupplyIndex_, assets, Rounding.DOWN) : 0;
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     * @param assets The amount of assets to deposit
     * @return The total amount of shares that would be minted by the deposit
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        if (comet.isTransferPaused()) return 0;
        if (assets == type(uint256).max) assets = IERC20(asset()).balanceOf(msg.sender);
        // Calculate shares to mint by calculating the new principal amount
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        if(baseSupplyIndex_ == 0) return 0;
        uint256 currentPrincipal = totalSupply();
        uint256 newBalance = totalAssets() + assets;
        // Round down so accounting is in the wrapper's favor
        uint104 newPrincipal = principalValueSupply(baseSupplyIndex_, newBalance, Rounding.DOWN);
        uint256 shares = newPrincipal - currentPrincipal;
        return shares;
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given
     * current on-chain conditions.
     * @param shares The amount of shares to mint
     * @return The total amount of assets required to mint the given shares
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        if (comet.isTransferPaused()) return 0;
        // Back out the quantity of assets to deposit in order to increment principal by `shares`
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        if(baseSupplyIndex_ == 0) return 0;
        uint256 currentPrincipal = totalSupply();
        uint256 newPrincipal = currentPrincipal + shares;
        // Round up so accounting is in the wrapper's favor
        uint256 newBalance = presentValueSupply(baseSupplyIndex_, newPrincipal, Rounding.UP);
        uint256 assets = newBalance - totalAssets();
        return assets;
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     * @param assets The amount of assets to withdraw
     * @return The total amount of shares required to withdraw the given assets
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        if (comet.isTransferPaused()) return 0;
        // Calculate the quantity of shares to burn by calculating the new principal amount
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        if(baseSupplyIndex_ == 0) return 0;
        uint256 currentPrincipal = totalSupply();
        uint256 currentBalance = totalAssets();
        uint256 newBalance = currentBalance > assets ? currentBalance - assets : 0;
        // Round down so accounting is in the wrapper's favor
        uint104 newPrincipal = principalValueSupply(baseSupplyIndex_, newBalance, Rounding.DOWN);
        return currentPrincipal > newPrincipal ? currentPrincipal - newPrincipal : 0;
    }

    /**
     * @notice Allows an on-chain or off-chain user to simulate the effects of their redemption at the current block,
     * given current on-chain conditions.
     * @param shares The amount of shares to redeem
     * @return The total amount of assets that would be withdrawn by the redemption
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        if (comet.isTransferPaused()) return 0;
        // Back out the quantity of assets to withdraw in order to decrement principal by `shares`
        uint64 baseSupplyIndex_ = accruedSupplyIndex();
        if(baseSupplyIndex_ == 0) return 0;
        uint256 currentPrincipal = totalSupply();
        uint256 newPrincipal = currentPrincipal > shares ? currentPrincipal - shares : 0;
        // Round up so accounting is in the wrapper's favor
        uint256 newBalance = presentValueSupply(baseSupplyIndex_, newPrincipal, Rounding.UP);
        uint256 currentBalance = totalAssets();
        return currentBalance > newBalance ? currentBalance - newBalance : 0;
    }

    /**
     * @notice Maximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault,
     * through a withdraw call.
     * @param owner The owner of the assets to be withdrawn
     * @return The total amount of assets that could be withdrawn
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return previewRedeem(balanceOf(owner));
    }

    /**
     * @dev The current timestamp
     * From https://github.com/compound-finance/comet/blob/main/contracts/Comet.sol#L375-L378
     */
    function getNowInternal() internal view returns (uint40) {
        if (block.timestamp >= 2**40) revert TimestampTooLarge();
        return uint40(block.timestamp);
    }

    /**
     * @notice Returns the domain separator used in the encoding of the signature for permit
     * @return bytes32 The domain separator
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), keccak256(bytes(VERSION)), block.chainid, address(this)));
    }

    /**
     * @notice Sets approval amount for a spender via signature from signatory
     * @param owner The address that signed the signature
     * @param spender The address to authorize (or rescind authorization from)
     * @param amount Amount that `owner` is approving for `spender`
     * @param deadline Expiration time for the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp >= deadline) revert SignatureExpired();

        uint256 nonce = nonces[owner];
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (isValidSignature(owner, digest, v, r, s)) {
            nonces[owner]++;
            _approve(owner, spender, amount);
        } else {
            revert BadSignatory();
        }
    }

    /**
     * @notice Checks if a signature is valid
     * @dev Supports EIP-1271 signatures for smart contracts
     * @param signer The address that signed the signature
     * @param digest The hashed message that is signed
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     * @return bool Whether the signature is valid
     */
    function isValidSignature(
        address signer,
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        if (hasCode(signer)) {
            bytes memory signature = abi.encodePacked(r, s, v);
            (bool success, bytes memory data) = signer.staticcall(
                abi.encodeCall(IERC1271.isValidSignature, (digest, signature))
            );
            if (!success || data.length != 32) revert EIP1271VerificationFailed();
            bytes4 returnValue = abi.decode(data, (bytes4));
            return returnValue == EIP1271_MAGIC_VALUE;
        } else {
            (address recoveredSigner, ECDSA.RecoverError recoverError) = ECDSA.tryRecover(digest, v, r, s);
            if (recoverError == ECDSA.RecoverError.InvalidSignatureS) revert InvalidSignatureS();
            if (recoverError == ECDSA.RecoverError.InvalidSignature) revert BadSignatory();
            if (recoveredSigner != signer) revert BadSignatory();
            return true;
        }
    }

    /**
     * @notice Checks if an address has code deployed to it
     * @param addr The address to check
     * @return bool Whether the address contains code
     */
    function hasCode(address addr) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}
