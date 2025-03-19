// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { CoreTest, TransparentUpgradeableProxy } from "./CoreTest.sol";
import { CometWrapper, ICometRewards, CometHelpers, IERC20, CometInterface } from "../src/CometWrapper.sol";
import { Deployable, ICometConfigurator, ICometProxyAdmin } from "../src/vendor/ICometConfigurator.sol";
import { CometWrapperWithoutMultiplier, ICometRewardsWithoutMultiplier } from "../src/CometWrapperWithoutMultiplier.sol";
import { MockCometRewards } from "../src/test/MockCometRewards.sol";
import { MockCometRewardsWithoutMultiplier } from "../src/test/MockCometRewardsWithoutMultiplier.sol";

abstract contract RewardsTest is CoreTest {
    function test_getRewardOwed(uint256 aliceAmount, uint256 bobAmount) public {
        /* ===== Setup ===== */

        (aliceAmount, bobAmount) = setUpFuzzTestAssumptions(aliceAmount, bobAmount);

        enableRewardsAccrual();

        // Make amount an even number so it can be divided equally by 2
        if (aliceAmount % 2 != 0) aliceAmount -= 1;
        if (bobAmount % 2 != 0) bobAmount -= 1;

        vm.stopPrank();
        deal(address(underlyingToken), cometHolder, aliceAmount + bobAmount);

        // Alice and Bob have same amount of funds in both CometWrapper and Comet
        vm.startPrank(cometHolder);
        comet.transfer(alice, cometWrapper.previewDeposit(aliceAmount / 2));
        comet.transfer(bob, cometWrapper.previewDeposit(bobAmount / 2));
        underlyingToken.transfer(alice, aliceAmount / 2);
        underlyingToken.transfer(bob, bobAmount / 2);
        vm.stopPrank();

        vm.startPrank(alice);
        underlyingToken.approve(address(cometWrapper), aliceAmount / 2);
        cometWrapper.deposit(aliceAmount / 2, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        underlyingToken.approve(address(cometWrapper), bobAmount / 2);
        cometWrapper.deposit(bobAmount / 2, bob);
        vm.stopPrank();

        // Make sure that Alice and Bob have the same amount of shares in Comet and the CometWrapper
        // We do this because `comet.transfer` can burn 1 extra principal from the sender
        (int104 principal,,,,) = comet.userBasic(alice);
        uint256 diffInShares = cometWrapper.balanceOf(alice) - uint256(int256(principal));
        if (diffInShares > 0) {
            vm.prank(alice);
            cometWrapper.redeem(diffInShares, address(1), alice);
        }
        (principal,,,,) = comet.userBasic(bob);
        diffInShares = cometWrapper.balanceOf(bob) - uint256(int256(principal));
        if (diffInShares > 0) {
            vm.prank(bob);
            cometWrapper.redeem(diffInShares, address(1), bob);
        }

        /* ===== Start test ===== */

        assertApproxEqAbs(cometWrapper.totalAssets(), comet.balanceOf(wrapperAddress), 3);
        // Rewards accrual will not be applied retroactively
        assertApproxEqAbs(cometWrapper.getRewardOwed(alice, true), 0, 4);
        assertApproxEqAbs(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed, 4);

        skip(7 days);

        // Rewards accrual in CometWrapper matches rewards accrual in Comet
        assertGt(cometWrapper.getRewardOwed(alice, true), 0);
        assertApproxEqAbs(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed, 4);

        assertGt(cometWrapper.getRewardOwed(bob, true), 0);
        assertApproxEqAbs(cometWrapper.getRewardOwed(bob, true), cometRewards.getRewardOwed(cometAddress, bob).owed, 4);

        // The wrapper should always be owed the same or more rewards from Comet
        // than the sum of rewards owed to its depositors
        assertGe(
            cometRewards.getRewardOwed(cometAddress, wrapperAddress).owed,
            cometWrapper.getRewardOwed(bob, true) + cometWrapper.getRewardOwed(alice, true)
        );
    }

    function test_getRewardOwed_revertsOnUninitializedReward() public {
        // Set up new reward contract with uninitialized reward token
        address mockRewards;
        if(block.chainid == 1) { // mainnet
            MockCometRewardsWithoutMultiplier mockRewardsContract = new MockCometRewardsWithoutMultiplier();
            mockRewardsContract.setConfig(ICometRewardsWithoutMultiplier.RewardConfig(address(1), 0, false));
            mockRewards = address(mockRewardsContract);
        } else if(block.chainid == 8453) { // base
            MockCometRewards mockRewardsContract = new MockCometRewards();
            mockRewardsContract.setConfig(ICometRewards.RewardConfig(address(1), 0, false, 0));
            mockRewards = address(mockRewardsContract);
        }

        CometWrapper cometWrapperImpl = CometWrapper(deployWrapperImplementationForGivenChain(cometAddress, mockRewards));
        TransparentUpgradeableProxy cometWrapperProxy = new TransparentUpgradeableProxy(address(cometWrapperImpl), proxyAdminAddress, "");
        CometWrapper newCometWrapper = CometWrapper(address(cometWrapperProxy));
        newCometWrapper.initialize("Wrapped Comet UNDERLYING", "WcUNDERLYINGv3");

        if(block.chainid == 1) { // mainnet
            MockCometRewardsWithoutMultiplier mockRewardsContract = MockCometRewardsWithoutMultiplier(mockRewards);
            mockRewardsContract.setConfig(ICometRewardsWithoutMultiplier.RewardConfig(address(0), 0, false));
        } else if(block.chainid == 8453) { // base
            MockCometRewards mockRewardsContract = MockCometRewards(mockRewards);
            mockRewardsContract.setConfig(ICometRewards.RewardConfig(address(0), 0, false, 0));
        }
        vm.prank(alice);
        vm.expectRevert(CometWrapper.UninitializedReward.selector);
        newCometWrapper.getRewardOwed(alice, true);
    }

    function test_claimTo(uint256 aliceAmount, uint256 bobAmount) public {
        /* ===== Setup ===== */

        (aliceAmount, bobAmount) = setUpFuzzTestAssumptions(aliceAmount, bobAmount);

        enableRewardsAccrual();
        // Make sure CometRewards has ample COMP to claim
        deal(address(comp), address(cometRewards), 100_000_000 ether);
        deal(address(underlyingToken), cometHolder, aliceAmount + bobAmount);

        // Make amount an even number so it can be divided equally by 2
        if (aliceAmount % 2 != 0) aliceAmount -= 1;
        if (bobAmount % 2 != 0) bobAmount -= 1;

        vm.startPrank(cometHolder);
        comet.transfer(alice, aliceAmount / 2);
        comet.transfer(bob, cometWrapper.previewDeposit(bobAmount / 2));
        underlyingToken.transfer(alice, cometWrapper.previewMint(aliceAmount / 2));
        underlyingToken.transfer(bob, bobAmount / 2);
        vm.stopPrank();

        vm.startPrank(alice);
        underlyingToken.approve(address(cometWrapper), cometWrapper.previewMint(aliceAmount / 2) + 50);
        cometWrapper.mint(aliceAmount / 2, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        underlyingToken.approve(address(cometWrapper), bobAmount / 2);
        cometWrapper.deposit(bobAmount / 2, bob);
        vm.stopPrank();

        // Make sure that Alice and Bob have the same amount of shares in Comet and the CometWrapper
        // We do this because `comet.transfer` can burn 1 extra principal from the sender
        (int104 principal,,,,) = comet.userBasic(alice);
        int256 diffInShares = int256(cometWrapper.balanceOf(alice)) - int256(principal);
        if (diffInShares > 0) {
            vm.prank(alice);
            cometWrapper.redeem(uint256(diffInShares), address(1), alice);
        }
        (principal,,,,) = comet.userBasic(bob);
        diffInShares = int256(cometWrapper.balanceOf(bob)) - int256(principal);
        if (diffInShares > 0) {
            vm.prank(bob);
            cometWrapper.redeem(uint256(diffInShares), address(1), bob);
        }

        /* ===== Start test ===== */

        skip(30 days);

        // Accrued rewards in CometWrapper matches accrued rewards in Comet
        uint256 rewardsFromComet;
        uint256 wrapperRewards;
        vm.startPrank(alice);
        cometRewards.claim(cometAddress, alice, true);
        rewardsFromComet = comp.balanceOf(alice);
        cometWrapper.claimTo(alice, true);
        wrapperRewards = comp.balanceOf(alice) - rewardsFromComet;
        vm.stopPrank();

        assertEq(wrapperRewards, rewardsFromComet);

        skip(2188 days);

        vm.startPrank(bob);
        cometRewards.claim(cometAddress, bob, true);
        rewardsFromComet = comp.balanceOf(bob);
        cometWrapper.claimTo(bob, true);
        wrapperRewards = comp.balanceOf(bob) - rewardsFromComet;
        vm.stopPrank();

        assertEq(wrapperRewards, rewardsFromComet);
    }

    function test_getClaimTo_revertsOnUninitializedReward() public {
        // Set up new reward contract with uninitialized reward token
        address mockRewards;
        if(block.chainid == 1) { // mainnet
            MockCometRewardsWithoutMultiplier mockRewardsContract = new MockCometRewardsWithoutMultiplier();
            mockRewardsContract.setConfig(ICometRewardsWithoutMultiplier.RewardConfig(address(1), 0, false));
            mockRewards = address(mockRewardsContract);
        } else if(block.chainid == 8453) { // base
            MockCometRewards mockRewardsContract = new MockCometRewards();
            mockRewardsContract.setConfig(ICometRewards.RewardConfig(address(1), 0, false, 0));
            mockRewards = address(mockRewardsContract);
        }

        CometWrapper cometWrapperImpl = CometWrapper(deployWrapperImplementationForGivenChain(cometAddress, mockRewards));
        TransparentUpgradeableProxy cometWrapperProxy = new TransparentUpgradeableProxy(address(cometWrapperImpl), proxyAdminAddress, "");
        CometWrapper newCometWrapper = CometWrapper(address(cometWrapperProxy));
        newCometWrapper.initialize("Wrapped Comet UNDERLYING", "WcUNDERLYINGv3");

        if(block.chainid == 1) { // mainnet
            MockCometRewardsWithoutMultiplier mockRewardsContract = MockCometRewardsWithoutMultiplier(mockRewards);
            mockRewardsContract.setConfig(ICometRewardsWithoutMultiplier.RewardConfig(address(0), 0, false));
        } else if(block.chainid == 8453) { // base
            MockCometRewards mockRewardsContract = MockCometRewards(mockRewards);
            mockRewardsContract.setConfig(ICometRewards.RewardConfig(address(0), 0, false, 0));
        }
        vm.prank(alice);
        vm.expectRevert(CometWrapper.UninitializedReward.selector);
        newCometWrapper.claimTo(alice, true);
    }

    function test_constructor_revertsOnBadRewards() public {
        if(block.chainid == 1) { // mainnet
            MockCometRewardsWithoutMultiplier mockRewardsContract = new MockCometRewardsWithoutMultiplier();
            vm.expectRevert(CometWrapper.BadRewards.selector);
            new CometWrapperWithoutMultiplier(comet, ICometRewardsWithoutMultiplier(address(mockRewardsContract)));
        
        } else if(block.chainid == 8453) { // base
            MockCometRewards mockRewardsContract = new MockCometRewards();
            vm.expectRevert(CometWrapper.BadRewards.selector);
            new CometWrapper(comet, ICometRewards(address(mockRewardsContract)));
        }
    }

    function test_accrueRewards(uint256 aliceAmount) public {
        /* ===== Setup ===== */

        aliceAmount = setUpFuzzTestAssumptions(aliceAmount);

        enableRewardsAccrual();

        // Make amount an even number so it can be divided equally by 2
        if (aliceAmount % 2 != 0) aliceAmount -= 1;

        vm.startPrank(cometHolder);
        comet.transfer(alice, aliceAmount / 2);
        vm.stopPrank();
        deal(address(underlyingToken), alice, cometWrapper.previewMint(aliceAmount));

        vm.startPrank(alice);
        underlyingToken.approve(address(cometWrapper), cometWrapper.previewMint(aliceAmount));
        cometWrapper.mint(aliceAmount / 2, alice);
        vm.stopPrank();

        // Make sure that Alice has the same amount of shares in Comet and the CometWrapper
        // We do this because `comet.transfer` can burn 1 extra principal from the sender
        (int104 principal,,,,) = comet.userBasic(alice);
        uint256 diffInShares = cometWrapper.balanceOf(alice) - uint256(int256(principal));
        if (diffInShares > 0) {
            vm.prank(alice);
            cometWrapper.redeem(diffInShares, address(1), alice);
        }

        /* ===== Start test ===== */

        skip(30 days);
        (uint64 baseTrackingAccrued,) = cometWrapper.userBasic(alice);
        assertEq(baseTrackingAccrued, 0);

        cometWrapper.accrueRewards(alice, true);
        (baseTrackingAccrued,) = cometWrapper.userBasic(alice);
        assertGt(baseTrackingAccrued, 0);
        assertApproxEqAbs(baseTrackingAccrued, comet.baseTrackingAccrued(address(cometWrapper)), 1);
    }

    // Tests that previously accrued rewards persist even after a user's Comet Wrapper balance changes
    function test_accrueRewardsBeforeBalanceChanges() public {
        enableRewardsAccrual();
        uint256 snapshot = vm.snapshot();

        setupAliceBalance();
        skip(30 days);
        vm.prank(alice);
        cometWrapper.transfer(bob, 5_000e6);

        // Alice should have 30 days worth of accrued rewards for her 10K WcUNDERLYING
        assertEq(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed);
        // Bob should have no rewards accrued yet since his balance prior to the transfer was 0
        assertEq(cometWrapper.getRewardOwed(bob, true), 0);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        setupAliceBalance();
        skip(30 days);
        vm.prank(alice);
        cometWrapper.redeem(5_000e6, alice, alice);

        // Alice should have 30 days worth of accrued rewards for her 10K WcUNDERLYING and not for 5K WcUNDERLYING
        assertEq(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        setupAliceBalance();
        skip(30 days);
        vm.prank(alice);
        cometWrapper.withdraw(5_000e6, alice, alice);

        // Alice should have 30 days worth of accrued rewards for her 10K WcUNDERLYING and not for 5K WcUNDERLYING
        assertEq(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();
        setupAliceBalance();
        skip(30 days);
        vm.stopPrank();
        deal(address(underlyingToken), alice, cometWrapper.previewMint(10_000e6) + 50);
        vm.startPrank(alice);
        underlyingToken.approve(address(cometWrapper), cometWrapper.previewMint(10_000e6) + 50);
        cometWrapper.mint(5_000e6, alice);
        vm.stopPrank();

        // Alice should have 30 days worth of accrued rewards for her 10K WcUNDERLYING and not for 5K WcUNDERLYING
        assertEq(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed);

        vm.revertTo(snapshot);
        snapshot = vm.snapshot();

        setupAliceBalance();
        skip(30 days);
        deal(address(underlyingToken), alice, 5_001e6);
        vm.startPrank(alice);
        underlyingToken.approve(address(cometWrapper), 5_001e6);
        cometWrapper.deposit(5_000e6, alice);
        vm.stopPrank();

        // Alice should have 30 days worth of accrued rewards for her 10K WcUNDERLYING and not for 5K WcUNDERLYING
        assertEq(cometWrapper.getRewardOwed(alice, true), cometRewards.getRewardOwed(cometAddress, alice).owed);
    }

    function setupAliceBalance() internal {
        vm.prank(cometHolder);
        comet.transfer(alice, 10_000e6);
        deal(address(underlyingToken), alice, 20_000e6);
        vm.startPrank(alice);
        underlyingToken.approve(address(cometWrapper), 10_000e6);
        cometWrapper.deposit(10_000e6, alice);
        vm.stopPrank();
    }

    function enableRewardsAccrual() internal {
        address governor = comet.governor();
        ICometConfigurator configurator = ICometConfigurator(configuratorAddress);
        ICometProxyAdmin proxyAdmin = ICometProxyAdmin(proxyAdminAddress);

        vm.startPrank(governor);
        configurator.setBaseTrackingSupplySpeed(cometAddress, 2e14); // 0.2 COMP/second
        proxyAdmin.deployAndUpgradeTo(Deployable(configuratorAddress), cometAddress);
        vm.stopPrank();
    }
}
