# AgentBounty — On-Chain Task-Bounty Escrow Skill for Pharos

> A submission to the **Pharos Skill-to-Agent Dual Cascade Hackathon — Phase 1 (Skill Hackathon)**.
> A reusable [Pharos Skill Engine](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide)
> module that gives AI agents a safe, composable way to **commission work and pay on completion**.

AgentBounty turns *"pay another agent to do a task"* into a single on-chain primitive.
A poster escrows a reward (native **PHRS** or any **ERC20**, e.g. PROS), workers submit
deliverable pointers, and the poster approves one worker — atomically releasing the reward.
Unanswered bounties can be cancelled; timed-out ones can be reclaimed. It is the
agent-economy building block Phase-2 Agents reuse instead of reinventing escrow.

## Why this skill

Mapped to the hackathon's judging criteria:

| Criterion | How AgentBounty delivers |
|-----------|--------------------------|
| **Practical use case for AI agents** | Agent-to-agent task markets need escrow; this is the missing payment rail. |
| **Reusability & composability** | A clean primitive — any Agent can call "post / submit / approve" to hire or get hired. |
| **Technical quality & completeness** | Single-file, dependency-free contract; 18 passing tests incl. fuzzing & non-standard ERC20s; reentrancy-guarded with checks-effects-interactions. |
| **Alignment with the Pharos vision** | On-chain payments + social interaction + agents transacting at scale. |
| **Docs & UX** | Full Skill Engine integration: `SKILL.md` capability index + a complete `references/bounty.md` with `cast`/`forge` templates, parameter tables, output parsing, error tables, and agent guidelines. |

## How it fits the Pharos Skill Engine

```
SKILL.md                         # capability index (agent entry point)
references/bounty.md             # per-operation reference (commands, params, errors, guidelines)
src/bounty/BountyBoard.sol       # the skill contract
assets/bounty/BountyBoard.sol    #   mirror, per Skill Engine convention
assets/networks.json             # Pharos testnet RPC / chain id / explorer
assets/tokens.json               # token registry (PHRS / PROS)
assets/templates/bounty.ts       # off-chain interaction template (viem)
script/bounty/DeployBountyBoard.s.sol
test/BountyBoard.t.sol           # 18 tests
```

## Lifecycle

```
postBounty ──> Open ──submitWork(*)──> Open ──approve(winner)──> Paid  (reward → winner)
                 │
                 ├── cancel()  (only while submissionCount == 0)  ──> Refunded (reward → poster)
                 └── reclaim() (only after a non-zero deadline)   ──> Refunded (reward → poster)
```

## Quickstart

```bash
# 1. Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Install deps, build, test
forge install foundry-rs/forge-std    # if lib/ is empty after clone
forge build
forge test -vvv

# 3. Configure your environment
cp .env.example .env                  # then edit .env with a TESTNET key
export $(grep -v '^#' .env | xargs)
export DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)

# 4. Deploy to Pharos Testnet (chain id 688688)
forge script script/bounty/DeployBountyBoard.s.sol \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
```

Get testnet PHRS for gas from the [Pharos faucet](https://testnet.pharosnetwork.xyz).
Then follow [`references/bounty.md`](references/bounty.md) to post, submit, and approve.

## Live deployment

`BountyBoard` is **deployed and source-verified** on **Pharos Atlantic Testnet** — the
testnet the Skill Engine guide itself targets (`RPC=https://atlantic.dplabs-internal.com`).

| | |
|---|---|
| Network | Pharos Atlantic Testnet |
| Chain ID | `688689` |
| **BountyBoard** | [`0xa71e7baB1cB82F1Ee67ca6A32aEBD47840C922aA`](https://atlantic.pharosscan.xyz/address/0xa71e7baB1cB82F1Ee67ca6A32aEBD47840C922aA) |
| Deploy tx | [`0x6dcddead908143b3a4117da5d17d0991650ab0cdb06c40ed15e7b5040893c209`](https://atlantic.pharosscan.xyz/tx/0x6dcddead908143b3a4117da5d17d0991650ab0cdb06c40ed15e7b5040893c209) |
| Source verified | ✅ yes |
| RPC | `https://atlantic.dplabs-internal.com` |
| Explorer | `https://atlantic.pharosscan.xyz` |
| Native coin | PHRS |

A full lifecycle was exercised against this live contract — bounty #1 was posted
(0.01 PHRS escrowed), a worker submitted, and the poster approved, releasing the reward
to the worker (`statusOf(1) == 2 Paid`). All of it is visible on the contract's explorer page.

> The same artifact deploys unchanged to **Pharos Testnet (chain 688688,
> `https://testnet.dplabs-internal.com`, explorer `https://testnet.pharosscan.xyz`)** —
> both networks are in `assets/networks.json`. Just point `--rpc-url` at the other RPC.

## Security notes

- Funds are pulled into escrow on `postBounty` and pushed out only on `approve`/`cancel`/`reclaim`.
- All payout paths are `nonReentrant` and update state **before** transferring (checks-effects-interactions).
- `cancel` is restricted to zero-submission bounties so a delivering worker is never rug-pulled;
  the timed-out path is the separate `reclaim`.
- Low-level token calls tolerate non-standard ERC20s (no-return tokens like USDT).
- ⚠️ Never commit a real private key. Use a dedicated **testnet** key; `.env` is gitignored.

## License

MIT
