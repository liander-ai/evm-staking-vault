// Interact with a deployed StakingVault using viem.
//
// Reads pool state, stakes tokens, (on a local anvil node) fast-forwards time
// to accrue rewards, then reads the pending reward. Works against a local anvil
// node or any EVM testnet.
//
// Env vars:
//   RPC_URL       e.g. http://127.0.0.1:8545  (or a testnet RPC)
//   CHAIN_ID      e.g. 31337 (anvil), 84532 (Base Sepolia), 97 (BNB testnet)
//   PRIVATE_KEY   deployer / user key
//   VAULT         deployed StakingVault address
//   STAKE_TOKEN   deployed stake-token address
//
// Run:  npm run interact
import {
  createPublicClient,
  createWalletClient,
  http,
  defineChain,
  parseEther,
  formatEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const RPC_URL = process.env.RPC_URL || "http://127.0.0.1:8545";
const CHAIN_ID = Number(process.env.CHAIN_ID || 31337);
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const VAULT = process.env.VAULT;
const STAKE_TOKEN = process.env.STAKE_TOKEN;

if (!PRIVATE_KEY || !VAULT || !STAKE_TOKEN) {
  throw new Error("Set PRIVATE_KEY, VAULT, and STAKE_TOKEN env vars.");
}

const chain = defineChain({
  id: CHAIN_ID,
  name: `chain-${CHAIN_ID}`,
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});

const account = privateKeyToAccount(
  PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`
);
const publicClient = createPublicClient({ chain, transport: http(RPC_URL) });
const walletClient = createWalletClient({ account, chain, transport: http(RPC_URL) });

const vaultAbi = [
  { type: "function", name: "rewardRate", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalStaked", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pendingRewards", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "stake", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  { type: "function", name: "claim", stateMutability: "nonpayable", inputs: [], outputs: [] },
];
const erc20Abi = [
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
];

async function rpc(method, params = []) {
  const res = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  return res.json();
}

async function main() {
  console.log("Account    :", account.address);
  console.log("Vault      :", VAULT);

  const rate = await publicClient.readContract({ address: VAULT, abi: vaultAbi, functionName: "rewardRate" });
  console.log("rewardRate :", rate.toString());

  const amount = parseEther("1000");

  let hash = await walletClient.writeContract({ address: STAKE_TOKEN, abi: erc20Abi, functionName: "approve", args: [VAULT, amount] });
  await publicClient.waitForTransactionReceipt({ hash });

  hash = await walletClient.writeContract({ address: VAULT, abi: vaultAbi, functionName: "stake", args: [amount] });
  await publicClient.waitForTransactionReceipt({ hash });

  const totalStaked = await publicClient.readContract({ address: VAULT, abi: vaultAbi, functionName: "totalStaked" });
  console.log("Staked 1000 -> totalStaked:", formatEther(totalStaked));

  // On a local anvil node we can fast-forward time to demonstrate accrual.
  if (CHAIN_ID === 31337) {
    await rpc("evm_increaseTime", [100000]);
    await rpc("evm_mine", []);
    console.log("(anvil) fast-forwarded 100,000s");
  }

  const pending = await publicClient.readContract({ address: VAULT, abi: vaultAbi, functionName: "pendingRewards", args: [account.address] });
  console.log("pendingRewards:", formatEther(pending));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
