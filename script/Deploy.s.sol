// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {DemoToken} from "../src/DemoToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploys two demo ERC-20s + the StakingVault, funds the reward pool,
///         and mints the deployer some stake tokens so it is immediately usable.
///
/// Run against a local anvil node:
///   anvil &
///   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 \
///     --private-key $PRIVATE_KEY --broadcast
///
/// Run against a testnet (e.g. Base Sepolia / BNB testnet):
///   forge script script/Deploy.s.sol --rpc-url $RPC_URL \
///     --private-key $PRIVATE_KEY --broadcast
contract Deploy is Script {
    // rewardRate = 1e6 scaled by ACC_PRECISION (1e12): 1000 staked tokens accrue
    // ~1 reward token per 1000 seconds. Small enough to be readable in a demo.
    uint256 constant REWARD_RATE = 1e6;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);

        vm.startBroadcast(pk);

        DemoToken stakeToken = new DemoToken("Demo Stake", "dSTK");
        DemoToken rewardToken = new DemoToken("Demo Reward", "dRWD");

        StakingVault vault = new StakingVault(IERC20(address(stakeToken)), IERC20(address(rewardToken)), REWARD_RATE);

        // Fund the reward pool with 1,000,000 reward tokens.
        rewardToken.mint(me, 1_000_000 ether);
        rewardToken.approve(address(vault), 1_000_000 ether);
        vault.fundRewards(1_000_000 ether);

        // Give the deployer 10,000 stake tokens to try staking.
        stakeToken.mint(me, 10_000 ether);

        vm.stopBroadcast();

        console.log("StakeToken :", address(stakeToken));
        console.log("RewardToken:", address(rewardToken));
        console.log("Vault      :", address(vault));
    }
}
