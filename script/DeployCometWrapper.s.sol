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

// Optional but suggested ENV vars:
// ETHERSCAN_KEY

contract DeployCometWrapper is Script {
    address[] COMET_ADDRESS_MAINNET=[0x3Afdc9BCA9213A35503b077a6072F3D0d5AB0840, 0x3D0bb1ccaB520A66e607822fC55BC921738fAFE3, 0xA17581A9E3356d9A858b789D68B4d866e593aE94, 0xc3d688B66703497DAA19211EEdff47f25384cdc3];
    string[] TOKEN_NAME_MAINNET=["Wrapped Comet USDT", "Wrapped Comet wstETH", "Wrapped Comet WETH", "Wrapped Comet USDC"];
    string[] TOKEN_SYMBOL_MAINNET=["wcUSDTv3", "wcWstETHv3", "wcWETHv3", "wcUSDCv3"];
    address REWARDS_ADDRESS_MAINNET=0x1B0e765F6224C21223AeA2af16c1C46E38885a40;
    address PROXY_ADMIN_ADDRESS_MAINNET=0x1EC63B5883C3481134FD50D5DAebc83Ecd2E8779;

    address[] COMET_ADDRESS_OPTIMISM=[0x2e44e174f7D53F0212823acC11C01A11d58c5bCB, 0x995E394b8B2437aC8Ce61Ee0bC610D617962B214, 0xE36A30D249f7761327fd973001A32010b521b6Fd];
    string[] TOKEN_NAME_OPTIMISM=["Wrapped Comet USDC", "Wrapped Comet USDT", "Wrapped Comet WETH"];
    string[] TOKEN_SYMBOL_OPTIMISM=["wcUSDCv3", "wcUSDTv3", "wcWETHv3"];
    address REWARDS_ADDRESS_OPTIMISM=0x443EA0340cb75a160F31A440722dec7b5bc3C2E9;
    address PROXY_ADMIN_ADDRESS_OPTIMISM=0x3C30B5a5A04656565686f800481580Ac4E7ed178;

    address[] COMET_ADDRESS_POLYGON=[0xF25212E676D1F7F89Cd72fFEe66158f541246445, 0xaeB318360f27748Acb200CE616E389A6C9409a07];
    string[] TOKEN_NAME_POLYGON=["Wrapped Comet USDC", "Wrapped Comet USDT"];
    string[] TOKEN_SYMBOL_POLYGON=["wcUSDCv3", "wcUSDTv3"];
    address REWARDS_ADDRESS_POLYGON=0x45939657d1CA34A8FA39A924B71D28Fe8431e581;
    address PROXY_ADMIN_ADDRESS_POLYGON=0xd712ACe4ca490D4F3E92992Ecf3DE12251b975F9;

    address[] COMET_ADDRESS_BASE=[0xb125E6687d4313864e53df431d5425969c15Eb2F, 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf, 0x46e6b214b524310239732D51387075E0e70970bf];
    string[] TOKEN_NAME_BASE=["Wrapped Comet USDC", "Wrapped Comet USDbC", "Wrapped Comet WETH"];
    string[] TOKEN_SYMBOL_BASE=["wcUSDCv3", "wcUSDbCv3", "wcWETHv3"];
    address REWARDS_ADDRESS_BASE=0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1;
    address PROXY_ADMIN_ADDRESS_BASE=0xbdE8F31D2DdDA895264e27DD990faB3DC87b372d;

    address[] COMET_ADDRESS_ARBITRUM=[0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA, 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf, 0x6f7D514bbD4aFf3BcD1140B7344b32f063dEe486, 0xd98Be00b5D27fc98112BdE293e487f8D4cA57d07];
    string[] TOKEN_NAME_ARBITRUM=["Wrapped Comet USDC.e", "Wrapped Comet USDC", "Wrapped Comet WETH", "Wrapped Comet USDT"];
    string[] TOKEN_SYMBOL_ARBITRUM=["wcUSDCev3", "wcUSDCv3", "wcWETHv3", "wcUSDTv3"];
    address REWARDS_ADDRESS_ARBITRUM=0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;
    address PROXY_ADMIN_ADDRESS_ARBITRUM=0xD10b40fF1D92e2267D099Da3509253D9Da4D715e;

    address[] COMET_ADDRESS_SCROLL=[0xB2f97c1Bd3bf02f5e74d13f02E3e26F93D77CE44];
    string[] TOKEN_NAME_SCROLL=["Wrapped Comet USDC"];
    string[] TOKEN_SYMBOL_SCROLL=["wcUSDCv3"];
    address REWARDS_ADDRESS_SCROLL=0x70167D30964cbFDc315ECAe02441Af747bE0c5Ee;
    address PROXY_ADMIN_ADDRESS_SCROLL=0x87A27b91f4130a25E9634d23A5B8E05e342bac50;

    TransparentUpgradeableProxy cometWrapperProxy;
    address[] internal cometAddresses;
    string[] internal tokenNames;
    string[] internal tokenSymbols;
    address internal rewardsAddr;
    address internal proxyAdminAddr;

    function run() public {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        uint256 chainId = block.chainid;
        if (chainId == 1) {
            cometAddresses = COMET_ADDRESS_MAINNET;
            tokenNames = TOKEN_NAME_MAINNET;
            tokenSymbols = TOKEN_SYMBOL_MAINNET;
            rewardsAddr = REWARDS_ADDRESS_MAINNET;
            proxyAdminAddr = PROXY_ADMIN_ADDRESS_MAINNET;
            for(uint i = 0; i < cometAddresses.length; i++) {
                printDeployInfo(tokenNames[i], tokenSymbols[i], cometAddresses[i]);
                console.log("Deploying CometWrapperWithoutMultiplier");
                deployCometWrapperWithoutMultiplier(cometAddresses[i], tokenNames[i], tokenSymbols[i]);
            }
        } else if(chainId == 10) {
            cometAddresses = COMET_ADDRESS_OPTIMISM;
            tokenNames = TOKEN_NAME_OPTIMISM;
            tokenSymbols = TOKEN_SYMBOL_OPTIMISM;
            rewardsAddr = REWARDS_ADDRESS_OPTIMISM;
            proxyAdminAddr = PROXY_ADMIN_ADDRESS_OPTIMISM;
            vm.startBroadcast(deployer);
            for(uint i = 0; i < cometAddresses.length; i++) {
                printDeployInfo(tokenNames[i], tokenSymbols[i], cometAddresses[i]);
                console.log("Deploying CometWrapper");
                deployCometWrapper(cometAddresses[i], tokenNames[i], tokenSymbols[i]);
            }
        } else if(chainId == 137) {
            cometAddresses = COMET_ADDRESS_POLYGON;
            tokenNames = TOKEN_NAME_POLYGON;
            tokenSymbols = TOKEN_SYMBOL_POLYGON;
            rewardsAddr = REWARDS_ADDRESS_POLYGON;
            proxyAdminAddr = PROXY_ADMIN_ADDRESS_POLYGON;
            vm.startBroadcast(deployer);
            for(uint i = 0; i < cometAddresses.length; i++) {
                printDeployInfo(tokenNames[i], tokenSymbols[i], cometAddresses[i]);
                console.log("Deploying CometWrapperWithoutMultiplier");
                deployCometWrapperWithoutMultiplier(cometAddresses[i], tokenNames[i], tokenSymbols[i]);
            }
        } else if(chainId == 8453) {
            cometAddresses = COMET_ADDRESS_BASE;
            tokenNames = TOKEN_NAME_BASE;
            tokenSymbols = TOKEN_SYMBOL_BASE;
            rewardsAddr = REWARDS_ADDRESS_BASE;
            proxyAdminAddr = PROXY_ADMIN_ADDRESS_BASE;
            vm.startBroadcast(deployer);
            for(uint i = 0; i < cometAddresses.length; i++) {
                printDeployInfo(tokenNames[i], tokenSymbols[i], cometAddresses[i]);
                console.log("Deploying CometWrapper");
                deployCometWrapper(cometAddresses[i], tokenNames[i], tokenSymbols[i]);
            }
        } else if(chainId == 42161){            
            cometAddresses = COMET_ADDRESS_ARBITRUM;
            tokenNames = TOKEN_NAME_ARBITRUM;
            tokenSymbols = TOKEN_SYMBOL_ARBITRUM;
            rewardsAddr = REWARDS_ADDRESS_ARBITRUM;
            proxyAdminAddr = PROXY_ADMIN_ADDRESS_ARBITRUM;
            vm.startBroadcast(deployer);
            for(uint i = 0; i < cometAddresses.length; i++) {
                printDeployInfo(tokenNames[i], tokenSymbols[i], cometAddresses[i]);
                console.log("Deploying CometWrapper");
                deployCometWrapper(cometAddresses[i], tokenNames[i], tokenSymbols[i]);
            }
        } else if(chainId == 534352){
            cometAddresses = vm.envAddress("COMET_ADDRESS_SCROLL", ",");
            tokenNames = vm.envString("TOKEN_NAME_SCROLL", ",");         // Wrapped Comet WETH || Wrapped Comet USDC
            tokenSymbols = vm.envString("TOKEN_SYMBOL_SCROLL", ",");     // wcWETHv3 || wcUSDCv3
            rewardsAddr = vm.envAddress("REWARDS_ADDRESS_SCROLL");
            proxyAdminAddr = vm.envAddress("PROXY_ADMIN_ADDRESS_SCROLL");
            vm.startBroadcast(deployer);
            for(uint i = 0; i < cometAddresses.length; i++) {
                printDeployInfo(tokenNames[i], tokenSymbols[i], cometAddresses[i]);
                console.log("Deploying CometWrapper");
                deployCometWrapper(cometAddresses[i], tokenNames[i], tokenSymbols[i]);
            }
        }
        else {
            console.log("Unsupported chainId: ", chainId);
        }

        vm.stopBroadcast();
    }

    function printDeployInfo(
        string memory tokenName,
        string memory tokenSymbol,
        address cometAddr
    ) public view {    
        console.log("=============================================================");
        console.log("Token Name:      ", tokenName);
        console.log("Token Symbol:    ", tokenSymbol);
        console.log("Comet Address:   ", cometAddr);
        console.log("Rewards Address: ", rewardsAddr);
        console.log("Proxy Admin Address: ", proxyAdminAddr);
        console.log("=============================================================");
        }

    function deployCometWrapper(
        address cometAddr,
        string memory tokenName,
        string memory tokenSymbol
    ) internal {
        CometWrapper cometWrapperImpl =
            new CometWrapper(CometInterface(cometAddr), ICometRewards(rewardsAddr));
        cometWrapperProxy = new TransparentUpgradeableProxy(address(cometWrapperImpl), proxyAdminAddr, "");

        // Wrap in ABI to support easier calls
        CometWrapper cometWrapper = CometWrapper(address(cometWrapperProxy));

        // Initialize the wrapper contract
        cometWrapper.initialize(tokenName, tokenSymbol);
    }

    function deployCometWrapperWithoutMultiplier(
        address cometAddr,
        string memory tokenName,
        string memory tokenSymbol
    ) internal {
        CometWrapperWithoutMultiplier cometWrapperImpl =
            new CometWrapperWithoutMultiplier(CometInterface(cometAddr), ICometRewardsWithoutMultiplier(rewardsAddr));
        cometWrapperProxy = new TransparentUpgradeableProxy(address(cometWrapperImpl), proxyAdminAddr, "");

        // Wrap in ABI to support easier calls
        CometWrapperWithoutMultiplier cometWrapper = CometWrapperWithoutMultiplier(address(cometWrapperProxy));

        // Initialize the wrapper contract
        cometWrapper.initialize(tokenName, tokenSymbol);
    }
}
