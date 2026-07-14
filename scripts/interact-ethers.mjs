// Read the deployed StakingVault using ethers.js (v6) — the ethers counterpart
// to scripts/interact.mjs (which uses viem). Read-only, so it needs no gas.
//
//   RPC_URL=... VAULT=0x... USER_ADDR=0x... npm run read:ethers
import { ethers } from "ethers";

const RPC_URL = process.env.RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com";
const VAULT = process.env.VAULT || "0x5be7F333d78e81e364e040DaAB31D4435B255B95";
const USER = process.env.USER_ADDR || "0xF2488C641460a1563F84a8429F3f725A55B2A4c0";

const abi = [
  "function rewardRate() view returns (uint256)",
  "function totalStaked() view returns (uint256)",
  "function pendingRewards(address) view returns (uint256)",
];

const provider = new ethers.JsonRpcProvider(RPC_URL);
const vault = new ethers.Contract(VAULT, abi, provider);

console.log("Vault        :", VAULT);
console.log("rewardRate   :", (await vault.rewardRate()).toString());
console.log("totalStaked  :", ethers.formatEther(await vault.totalStaked()));
console.log("pendingRewards:", ethers.formatEther(await vault.pendingRewards(USER)));
