---
name: bounty
title: AgentBounty — On-Chain Task-Bounty Escrow
description: >-
  Escrow-backed task bounties for the Pharos AI Agent economy. Lets any wallet or
  agent post a task with a reward held in escrow (native PHRS or any ERC20 such as
  PROS), lets other agents submit work, and lets the poster approve one worker to
  release payment — or cancel/reclaim for a refund. A composable "hire another agent
  for X" primitive for Pharos.
network: pharos_atlantic_testnet
chainId: 688689
deployedAddress: "0xa71e7baB1cB82F1Ee67ca6A32aEBD47840C922aA"
verified: true
version: 0.1.0
license: MIT
---

# AgentBounty Skill

AgentBounty turns "pay an agent to do a task" into a single, safe, reusable on-chain
flow. It is a building block: any Phase-2 Agent that needs to **commission work and pay
on completion** can call this skill instead of reinventing escrow.

**Lifecycle:** `postBounty` → `submitWork` (workers) → `approve` (pay winner) — with
`cancel` (no submissions yet) and `reclaim` (after deadline) as the refund paths.

- **Live & verified:** [`0xa71e7baB1cB82F1Ee67ca6A32aEBD47840C922aA`](https://atlantic.pharosscan.xyz/address/0xa71e7baB1cB82F1Ee67ca6A32aEBD47840C922aA) on Pharos Atlantic Testnet (688689). Also deploys to Pharos Testnet 688688 unchanged.
- Contract: `src/bounty/BountyBoard.sol` (mirror in `assets/bounty/BountyBoard.sol`)
- Deploy script: `script/bounty/DeployBountyBoard.s.sol`
- Full operation reference: [`references/bounty.md`](references/bounty.md)
- Network config: `assets/networks.json` · Tokens: `assets/tokens.json`
- Off-chain template (viem): `assets/templates/bounty.ts`

## Capability Index

| User Need | Capability | Instructions |
|-----------|------------|--------------|
| "Deploy the bounty skill / set up the bounty board" | `forge script` deploy | → [references/bounty.md](references/bounty.md#deploy-bountyboard) |
| "Post a bounty / offer X PHRS for a task" | `postBounty` (native) | → [references/bounty.md](references/bounty.md#post-a-bounty-native-phrs) |
| "Post a bounty paid in PROS / an ERC20 token" | `approve` + `postBounty` (ERC20) | → [references/bounty.md](references/bounty.md#post-a-bounty-erc20-eg-pros) |
| "Submit my work / apply for a bounty" | `submitWork` | → [references/bounty.md](references/bounty.md#submit-work) |
| "Approve a worker / pay the winner / release the reward" | `approve` | → [references/bounty.md](references/bounty.md#approve-a-winner-release-reward) |
| "Cancel my bounty / get my money back" | `cancel` or `reclaim` | → [references/bounty.md](references/bounty.md#cancel-no-submissions--reclaim-after-deadline) |
| "Show a bounty / is it still open / how much time left" | `getBounty` / `isOpen` / `timeLeft` / `statusOf` | → [references/bounty.md](references/bounty.md#read-bounty-state-view) |
| "Verify the contract on the explorer" | `forge verify-contract` | → [references/bounty.md](references/bounty.md#verify-the-contract-on-pharosscan-optional) |

## Quick facts for the agent

- Native reward → `token = 0x0000000000000000000000000000000000000000`, send `--value == amount`.
- ERC20 reward → `approve` the board first, send NO `--value`.
- Amounts are in wei: `cast to-wei <n> ether`.
- Status codes from views: `0 None`, `1 Open`, `2 Paid`, `3 Refunded`.
- Always read state (`getBounty` / `statusOf`) before and after a write to confirm it landed.
- Safety: reentrancy-guarded, checks-effects-interactions, tolerant of non-standard ERC20s.
