// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { CometWrapper, CometInterface, ICometRewards, CometHelpers, IERC20 } from "../src/CometWrapper.sol";
import { CometWrapperWithoutMultiplier, ICometRewardsWithoutMultiplier } from "../src/CometWrapperWithoutMultiplier.sol";

// Deploy with:
// $ set -a && source .env && ./script/deploy.sh

// Required ENV vars:
// RPC_URL
// DEPLOYER_PK
// COMET_ADDRESS
// REWARDS_ADDRESS
// PROXY_ADMIN_ADDRESS
// TOKEN_NAME
// TOKEN_SYMBOL

// Optional but suggested ENV vars:
// ETHERSCAN_KEY

contract DeploySingleCometWrapper is Script {
    TransparentUpgradeableProxy cometWrapperProxy;
    address internal cometAddress;
    string internal tokenName;
    string internal tokenSymbol;
    address internal rewardsAddr;
    address internal proxyAdminAddr;
    bool internal withMultiplier;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        cometAddress = vm.envAddress("COMET_ADDRESS");
        rewardsAddr = vm.envAddress("REWARDS_ADDRESS");
        proxyAdminAddr = vm.envAddress("PROXY_ADMIN_ADDRESS");
        tokenName = vm.envString("TOKEN_NAME"); // Wrapped Comet WETH || Wrapped Comet USDC
        tokenSymbol = vm.envString("TOKEN_SYMBOL");  // wcWETHv3 || wcUSDCv3
        withMultiplier = vm.envBool("WITH_MULTIPLIER");

        vm.startBroadcast(deployer);

        console.log("=============================================================");
        console.log("Token Name:           ", tokenName);
        console.log("Token Symbol:         ", tokenSymbol);
        console.log("Comet Address:        ", cometAddress);
        console.log("Rewards Address:      ", rewardsAddr);
        console.log("Proxy Admin Address:  ", proxyAdminAddr);

        if (withMultiplier) {
            deployCometWrapper();
        } else {
            deployCometWrapperWithoutMultiplier();
        }

        vm.stopBroadcast();
    }

    function printDeployInfo() public view {    
        }

    function deployCometWrapper() internal {
        CometWrapper cometWrapperImpl =
            new CometWrapper(CometInterface(cometAddress), ICometRewards(rewardsAddr));
        cometWrapperProxy = new TransparentUpgradeableProxy(address(cometWrapperImpl), proxyAdminAddr, "");

        // Wrap in ABI to support easier calls
        CometWrapper cometWrapper = CometWrapper(address(cometWrapperProxy));

        console.log("CometWrapper address: ", address(cometWrapper));
        console.log("=============================================================");
        console.log();

        // Initialize the wrapper contract
        cometWrapper.initialize(tokenName, tokenSymbol);
    }

    function deployCometWrapperWithoutMultiplier() internal {
        CometWrapperWithoutMultiplier cometWrapperImpl =
            new CometWrapperWithoutMultiplier(CometInterface(cometAddress), ICometRewardsWithoutMultiplier(rewardsAddr));
        cometWrapperProxy = new TransparentUpgradeableProxy(address(cometWrapperImpl), proxyAdminAddr, "");

        // Wrap in ABI to support easier calls
        CometWrapperWithoutMultiplier cometWrapper = CometWrapperWithoutMultiplier(address(cometWrapperProxy));

        console.log("CometWrapper address: ", address(cometWrapper));
        console.log("=============================================================");
        console.log();

        // Initialize the wrapper contract
        cometWrapper.initialize(tokenName, tokenSymbol);
    }
}
