// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal mintable ERC-20 used only for tests.
contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingVaultTest is Test {
    StakingVault vault;
    MockERC20 stakeToken;
    MockERC20 rewardToken;

    address admin = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // rewardRate = 1e6 (scaled by ACC_PRECISION = 1e12).
    // With 1000e18 staked: reward = 1000e18 * elapsed * 1e6 / 1e12 = 1000e18 * elapsed / 1e6.
    //   elapsed 100_000s -> 100e18 (100 tokens);  elapsed 150_000s -> 150e18 (150 tokens).
    uint256 constant RATE = 1e6;
    uint256 constant STAKE_AMT = 1000e18;

    function setUp() public {
        stakeToken = new MockERC20("Stake", "STK");
        rewardToken = new MockERC20("Reward", "RWD");
        vault = new StakingVault(IERC20(address(stakeToken)), IERC20(address(rewardToken)), RATE);

        // admin funds the reward pool
        rewardToken.mint(admin, 1_000_000e18);
        rewardToken.approve(address(vault), type(uint256).max);
        vault.fundRewards(1_000_000e18);

        // stakers get tokens + approve the vault
        stakeToken.mint(alice, 10_000e18);
        stakeToken.mint(bob, 10_000e18);
        vm.prank(alice);
        stakeToken.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        stakeToken.approve(address(vault), type(uint256).max);
    }

    /// Full path: stake -> accrue exactly 100 -> claim -> accrue exactly 150 ->
    /// claim -> unstake returns principal. Mirrors the Solana LiteSVM test.
    function test_full_lifecycle() public {
        vm.prank(alice);
        vault.stake(STAKE_AMT);
        assertEq(vault.totalStaked(), STAKE_AMT);

        vm.warp(block.timestamp + 100_000);
        assertEq(vault.pendingRewards(alice), 100e18, "should accrue exactly 100");

        vm.prank(alice);
        vault.claim();
        assertEq(rewardToken.balanceOf(alice), 100e18);

        vm.warp(block.timestamp + 150_000);
        assertEq(vault.pendingRewards(alice), 150e18, "should accrue exactly 150");

        vm.prank(alice);
        vault.claim();
        assertEq(rewardToken.balanceOf(alice), 250e18);

        vm.prank(alice);
        vault.unstake(STAKE_AMT);
        assertEq(vault.totalStaked(), 0);
        assertEq(stakeToken.balanceOf(alice), 10_000e18, "principal fully returned");
    }

    function test_stake_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingVault.ZeroAmount.selector);
        vault.stake(0);
    }

    function test_unstake_more_than_staked_reverts() public {
        vm.prank(alice);
        vault.stake(STAKE_AMT);
        vm.prank(alice);
        vm.expectRevert(StakingVault.InsufficientStake.selector);
        vault.unstake(STAKE_AMT + 1);
    }

    function test_claim_nothing_reverts() public {
        vm.prank(alice);
        vm.expectRevert(StakingVault.NothingToClaim.selector);
        vault.claim();
    }

    function test_fund_rewards_only_admin() public {
        vm.prank(alice);
        vm.expectRevert(StakingVault.NotAdmin.selector);
        vault.fundRewards(1e18);
    }

    /// Two stakers accrue independently in proportion to their stake.
    function test_two_stakers_accrue_independently() public {
        vm.prank(alice);
        vault.stake(STAKE_AMT); // 1000
        vm.prank(bob);
        vault.stake(STAKE_AMT * 2); // 2000

        vm.warp(block.timestamp + 100_000);

        assertEq(vault.pendingRewards(alice), 100e18);
        assertEq(vault.pendingRewards(bob), 200e18);
    }
}
