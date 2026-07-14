// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title StakingVault
/// @author Li Lander
/// @notice A token staking vault with linear, time-based rewards.
/// @dev EVM/Solidity port of the same protocol I built on Solana with Anchor
///      (see the anchor-staking-rewards repo). Users stake an ERC-20 token and
///      accrue a second ERC-20 reward token over time:
///
///        reward = stakedAmount * elapsedSeconds * rewardRate / ACC_PRECISION
///
///      Rewards are settled on every balance change, so a new stake never
///      retroactively changes past accrual. Solidity 0.8 has built-in overflow
///      checks, so the manual checked-math from the Rust/Anchor version is
///      handled by the compiler here.
contract StakingVault {
    using SafeERC20 for IERC20;

    /// @notice Fixed-point scaling for `rewardRate` (1e12) — same as the Solana version.
    uint256 public constant ACC_PRECISION = 1e12;

    /// @notice Account allowed to fund the reward pool.
    address public immutable admin;
    /// @notice Token users stake.
    IERC20 public immutable stakeToken;
    /// @notice Token paid out as rewards.
    IERC20 public immutable rewardToken;
    /// @notice Reward tokens per staked token per second, scaled by ACC_PRECISION.
    uint256 public immutable rewardRate;

    /// @notice Total amount currently staked across all users.
    uint256 public totalStaked;

    struct StakeInfo {
        uint256 amount; // tokens currently staked
        uint256 rewardDebt; // accrued, unclaimed rewards
        uint256 lastUpdate; // timestamp rewards were last settled
    }

    /// @notice Per-user stake state.
    mapping(address => StakeInfo) public stakes;

    event RewardsFunded(address indexed admin, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 reward);

    error ZeroAmount();
    error InsufficientStake();
    error NothingToClaim();
    error NotAdmin();

    /// @param _stakeToken Token users stake.
    /// @param _rewardToken Token paid out as rewards.
    /// @param _rewardRate Reward tokens per staked token per second, scaled by ACC_PRECISION.
    constructor(IERC20 _stakeToken, IERC20 _rewardToken, uint256 _rewardRate) {
        admin = msg.sender;
        stakeToken = _stakeToken;
        rewardToken = _rewardToken;
        rewardRate = _rewardRate;
    }

    /// @notice Admin tops up the reward pool so the vault can pay claims.
    function fundRewards(uint256 amount) external {
        if (msg.sender != admin) revert NotAdmin();
        if (amount == 0) revert ZeroAmount();
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsFunded(msg.sender, amount);
    }

    /// @notice Stake `amount` tokens. Settles pending rewards first so the new
    ///         balance does not retroactively change past accrual.
    function stake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        StakeInfo storage s = stakes[msg.sender];
        _settle(s);
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        s.amount += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    /// @notice Unstake `amount` tokens, settling rewards first.
    function unstake(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        StakeInfo storage s = stakes[msg.sender];
        if (s.amount < amount) revert InsufficientStake();
        _settle(s);
        s.amount -= amount;
        totalStaked -= amount;
        stakeToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Claim all accrued rewards.
    function claim() external {
        StakeInfo storage s = stakes[msg.sender];
        _settle(s);
        uint256 reward = s.rewardDebt;
        if (reward == 0) revert NothingToClaim();
        s.rewardDebt = 0;
        rewardToken.safeTransfer(msg.sender, reward);
        emit Claimed(msg.sender, reward);
    }

    /// @notice Total pending rewards for `user` (settled debt + unsettled accrual).
    function pendingRewards(address user) external view returns (uint256) {
        StakeInfo storage s = stakes[user];
        return s.rewardDebt + _accrued(s);
    }

    /// @dev Move newly-accrued rewards into `rewardDebt` and stamp `lastUpdate`.
    function _settle(StakeInfo storage s) internal {
        s.rewardDebt += _accrued(s);
        s.lastUpdate = block.timestamp;
    }

    /// @dev Rewards accrued since `lastUpdate` that are not yet in `rewardDebt`.
    function _accrued(StakeInfo storage s) internal view returns (uint256) {
        if (s.amount == 0 || s.lastUpdate == 0) {
            return 0;
        }
        uint256 elapsed = block.timestamp - s.lastUpdate;
        if (elapsed == 0) {
            return 0;
        }
        return (s.amount * elapsed * rewardRate) / ACC_PRECISION;
    }
}
