// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ICometRewardsWithoutMultiplier } from "../vendor/ICometRewardsWithoutMultiplier.sol";

contract MockCometRewardsWithoutMultiplier is ICometRewardsWithoutMultiplier {

    RewardConfig public config;

    function setConfig(RewardConfig memory _config) external {
        config = _config;
    }

    function rewardConfig(address) external view override returns (RewardConfig memory){
        return config;
    }

    function claim(address comet, address src, bool shouldAccrue) external override {}

    function getRewardOwed(address comet, address account) external override returns (RewardOwed memory){
        return RewardOwed(address(0), 0);
    }

    function claimTo(address comet, address src, address to, bool shouldAccrue) external override {}
}
