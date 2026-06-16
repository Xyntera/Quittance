/**
 * BountyBoard interaction template (viem).
 *
 * A minimal, copy-pasteable example showing how an off-chain agent drives the
 * BountyBoard skill on Pharos Testnet. Install: `npm i viem`.
 *
 * Env: PRIVATE_KEY (testnet), BOUNTY_BOARD (deployed address).
 */
import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  defineChain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

export const pharosTestnet = defineChain({
  id: 688688,
  name: "Pharos Testnet",
  nativeCurrency: { name: "Pharos", symbol: "PHRS", decimals: 18 },
  rpcUrls: { default: { http: ["https://testnet.dplabs-internal.com"] } },
  blockExplorers: {
    default: { name: "PharosScan", url: "https://testnet.pharosscan.xyz" },
  },
});

// Only the functions an agent typically needs. Full ABI is emitted by `forge build`
// at out/BountyBoard.sol/BountyBoard.json.
export const bountyBoardAbi = [
  {
    type: "function",
    name: "postBounty",
    stateMutability: "payable",
    inputs: [
      { name: "token", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "deadline", type: "uint64" },
      { name: "metadataURI", type: "string" },
    ],
    outputs: [{ name: "id", type: "uint256" }],
  },
  {
    type: "function",
    name: "submitWork",
    stateMutability: "nonpayable",
    inputs: [
      { name: "id", type: "uint256" },
      { name: "resultURI", type: "string" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "id", type: "uint256" },
      { name: "winner", type: "address" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "getBounty",
    stateMutability: "view",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [
      { name: "poster", type: "address" },
      { name: "token", type: "address" },
      { name: "reward", type: "uint256" },
      { name: "createdAt", type: "uint64" },
      { name: "deadline", type: "uint64" },
      { name: "submissionCount", type: "uint32" },
      { name: "status", type: "uint8" },
      { name: "winner", type: "address" },
      { name: "metadataURI", type: "string" },
    ],
  },
] as const;

async function main() {
  const account = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`);
  const board = process.env.BOUNTY_BOARD as `0x${string}`;

  const wallet = createWalletClient({ account, chain: pharosTestnet, transport: http() });
  const pub = createPublicClient({ chain: pharosTestnet, transport: http() });

  // Post a 1 PHRS native bounty with no deadline.
  const hash = await wallet.writeContract({
    address: board,
    abi: bountyBoardAbi,
    functionName: "postBounty",
    args: ["0x0000000000000000000000000000000000000000", parseEther("1"), 0n, "ipfs://<task-cid>"],
    value: parseEther("1"),
  });
  const receipt = await pub.waitForTransactionReceipt({ hash });
  console.log("posted in tx", receipt.transactionHash);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
