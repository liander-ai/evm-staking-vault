# EVM Staking Vault

A token staking vault with linear, time-based rewards, written in Solidity and tested with Foundry.

This is the **EVM/Solidity port of the same protocol I built on Solana with Anchor** ([`anchor-staking-rewards`](https://github.com/liander-ai/anchor-staking-rewards)). Same mechanics, two very different runtimes: an Anchor program in Rust on Solana, and a Solidity contract on the EVM. Building it twice is the point, the reward accounting and settlement rules are identical, only the platform primitives change.

## Live on Sepolia

Deployed and exercised on the Ethereum Sepolia testnet (a real `stake` transaction was executed via the viem script):

| Contract | Address |
| --- | --- |
| StakingVault | [`0x5be7F333d78e81e364e040DaAB31D4435B255B95`](https://sepolia.etherscan.io/address/0x5be7F333d78e81e364e040DaAB31D4435B255B95) |
| Stake token | [`0x64Bf6CdBfDF68E4Ea65E926d215707739f6eF5E0`](https://sepolia.etherscan.io/address/0x64Bf6CdBfDF68E4Ea65E926d215707739f6eF5E0) |
| Reward token | [`0x2eea1CffCB4f1bb07Ee97bAC6F5804AbE87DA3b5`](https://sepolia.etherscan.io/address/0x2eea1CffCB4f1bb07Ee97bAC6F5804AbE87DA3b5) |

## What it does

Users stake an ERC-20 token into the vault and accrue a second ERC-20 reward token over time:

```
reward = stakedAmount * elapsedSeconds * rewardRate / ACC_PRECISION
```

Rewards are **settled on every balance change**, so staking more never retroactively changes past accrual. `rewardRate` is expressed as reward tokens per staked token per second, scaled by `ACC_PRECISION` (1e12) for fixed-point precision, exactly like the Solana version.

### Contract API (`src/StakingVault.sol`)

| Function | Description |
| --- | --- |
| `constructor(stakeToken, rewardToken, rewardRate)` | Deploy the vault. Deployer becomes `admin`. |
| `fundRewards(amount)` | Admin tops up the reward pool. |
| `stake(amount)` | Stake tokens (settles pending rewards first). |
| `unstake(amount)` | Withdraw staked tokens (settles first). |
| `claim()` | Claim all accrued rewards. |
| `pendingRewards(user)` | View settled + unsettled rewards. |

Uses OpenZeppelin `SafeERC20`. Solidity 0.8 built-in overflow checks replace the manual checked-math from the Rust version. Custom errors: `ZeroAmount`, `InsufficientStake`, `NothingToClaim`, `NotAdmin`.

## Tests

Six Foundry tests, including an exact-accrual lifecycle that mirrors the Solana test suite (stake 1000 → accrue exactly 100 → claim → accrue exactly 150 → claim → unstake returns principal), plus guard reverts and independent multi-staker accrual.

```bash
forge test -vv
```

```
[PASS] test_claim_nothing_reverts()
[PASS] test_full_lifecycle()
[PASS] test_fund_rewards_only_admin()
[PASS] test_stake_zero_reverts()
[PASS] test_two_stakers_accrue_independently()
[PASS] test_unstake_more_than_staked_reverts()
Suite result: ok. 6 passed; 0 failed
```

## Local end-to-end (no testnet funds needed)

`local_e2e.sh` spins up a local [anvil](https://book.getfoundry.sh/anvil/) node, deploys the vault + two demo tokens with `forge script`, then drives it with the [viem](https://viem.sh) script, reading state, staking, fast-forwarding time, and reading accrued rewards:

```bash
bash local_e2e.sh
```

```
StakeToken : 0x5FbDB231...
Vault      : 0x9fE46736...
rewardRate : 1000000
Staked 1000 -> totalStaked: 1000
(anvil) fast-forwarded 100,000s
pendingRewards: 100
```

## Deploy to a testnet

```bash
cp .env.example .env      # fill in a throwaway PRIVATE_KEY + RPC_URL + CHAIN_ID
source .env
forge script script/Deploy.s.sol --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
```

The script deploys two demo ERC-20s + the vault, funds the reward pool, and mints the deployer stake tokens. Copy the printed `Vault` and `StakeToken` addresses into `.env`, then interact with viem:

```bash
npm install
npm run interact
```

## Stack

- **Solidity** `^0.8.24` (compiled with 0.8.28)
- **Foundry** (forge / anvil / cast) for build, test, and deploy
- **OpenZeppelin Contracts** v5 (`SafeERC20`, `ERC20`)
- **viem** for typed client-side interaction (`scripts/interact.mjs`), with an **ethers.js** read client too (`scripts/interact-ethers.mjs`, run `npm run read:ethers`)

## Layout

```
src/StakingVault.sol      the vault
src/DemoToken.sol         mintable ERC-20 for testnet demos
test/StakingVault.t.sol   Foundry tests
script/Deploy.s.sol       deployment script
scripts/interact.mjs      viem interaction script
local_e2e.sh              local anvil -> deploy -> viem proof
```

Dependencies are git submodules under `lib/`. After cloning:

```bash
forge install   # or: git submodule update --init --recursive
```

## License

MIT
