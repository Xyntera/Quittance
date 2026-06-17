# Quittance — DoraHacks Submission

> Pharos Skill-to-Agent Dual Cascade Hackathon · Phase 1 (Skill Hackathon)
> Repo: https://github.com/Xyntera/Quittance · License: MIT

## Tagline
**The settlement rail for the agent economy** — prepaid, gasless, programmable micropayments
on Pharos. Sign off-chain, settle on-chain. An x402-style payment primitive AI agents can call.

## Problem
AI agents need to *pay each other and pay for resources* — per API call, per task, per kWh — in
fractions of a cent, thousands of times a day. Today they can't:
- **Cards / Stripe**: account signups, ~30¢ minimums, chargebacks — micro-billing is impossible.
- **Plain on-chain transfers**: the payer signs and pays gas for *every* payment — unusable at
  high frequency, and there's no clean "pay-per-use" authorization.

## Solution
**Quittance** is an on-chain settlement contract — the credibly-neutral core of an
[x402](https://www.x402.org)-style flow:
1. A **payer deposits** funds once (native PHRS or any ERC20 stablecoin).
2. The payer **signs off-chain EIP-712 vouchers** — no gas, no API key — each authorizing a
   `payee` to receive a fixed `amount` for a `nonce` (the resource/idempotency id).
3. A server **`verify()`s** a voucher (read-only) before delivering the paid resource.
4. **Anyone** — the payee or a relayer/facilitator — calls **`redeem()`** (or `redeemMany()`)
   to settle on-chain. Single-use nonces prevent replay; the payer never pays settlement gas.

It's a **dependency, not an app**: any Phase-2 Agent that pays or gets paid calls
`deposit → sign → verify → redeem`.

## x402-aligned — and what it adds
Quittance is **not a fork of x402**; it's the on-chain settlement skill that makes x402-style
payments work on Pharos. x402 is an HTTP spec whose EVM "exact" scheme relies on the token's
**EIP-3009** `transferWithAuthorization` plus an off-chain facilitator. Quittance implements the
same *sign-off-chain / settle-on-chain* model as a reusable contract, and adds what EVM-x402
can't do natively. (It can also serve as the settlement backend a Pharos x402 facilitator calls.)

| Capability | Vanilla x402 (EIP-3009) | **Quittance** |
|---|---|---|
| Reusable on-chain contract | ✗ — HTTP spec + facilitator | ✓ a deployed Skill any agent calls |
| Token support | needs EIP-3009 tokens (USDC) | **native PHRS + any ERC-20** |
| Native coin payments | ✗ | ✓ |
| Gasless for the payer | ✓ | ✓ |
| Batched settlement | per-authorization | ✓ `redeemMany` — **100/tx proven live** |
| Prepaid, withdrawable budget | ✗ (pulls from wallet) | ✓ capped per-payer balance |
| Smart-account payers (EIP-1271) | varies | ✓ |
| Admin keys | n/a | **none** |

## What we built
- **`Quittance.sol`** — single-file, dependency-free settlement contract. Native + ERC20,
  EIP-712 vouchers, EIP-1271 (smart-account payers), `verify`/`redeem`/`redeemMany`/`withdraw`,
  **no owner / no admin keys / no protocol fee**.
- **Full Skill Engine integration** — `SKILL.md` capability index (Prerequisites, Network Config,
  Capability Index, Write-Op Pre-checks, Error Handling, Security), `references/quittance.md`
  (exact `cast`/`forge` templates, parameter/error tables, agent guidelines), `assets/` (networks,
  tokens, viem template).
- **Runnable agent-invocation harness** — `examples/agent/quittance-agent.mjs` drives the skill
  the exact way the Skill Engine's LLM does (read `SKILL.md` → match Capability Index → read
  reference → run `cast` → parse).
- **Tests & stress** — 14 unit tests, invariant testing (16,384 random calls, 0 reverts),
  1,024-run fuzzing, batch-scaling, and a live 100-voucher batch.
- **`VALIDATION.md`** — format-compliance matrix, publishing checklist, security self-review,
  and live on-chain evidence.

## Live proof (Pharos Atlantic Testnet, chain 688689)
- **Quittance (verified):** `0xd872C6F530c2E1055a522B1978CA99FE65B99F56`
  — https://atlantic.pharosscan.xyz/address/0xd872C6F530c2E1055a522B1978CA99FE65B99F56
- **Deploy tx:** `0xc9a52a8d47d7b3242994e628981d8fd36e45c5ddeb0d401a8b0326b3f709585d`
- **Agent deposit:** `0x696ef5a156e998d09f5ddcb0cf8c65bac5cb8182a7a014fd64cba89c48551c64`
- **Agent pay (sign→verify→redeem):** `0x8ce98165dbe805dbdda0801aa936814595808ee804402fe85b7d83c571301600`
- **Live 100-voucher batch in ONE tx:** `0x3c05b7190bb1f8d86b7bc5798d06f3c827ce064e4778497abd786d22f45c6d3f`
  (gas 4,398,434 ≈ 44k/voucher)

## Why it wins (mapped to the judging criteria)
| Criterion | Evidence |
|---|---|
| **Alignment with the Pharos vision** | Pharos = on-chain payments for the AI agent economy. Quittance *is* the settlement rail. |
| **Originality** | x402-*aligned* (Coinbase/Visa/Google; 119M+ txs) but adds native-coin + any-ERC20, batched settlement, and prepaid budgets EVM-x402 lacks — not a token/airdrop clone. |
| **Practical use for agents** | Gasless-for-payer, sub-cent, per-call payments; relayer-settled; works for EOAs and smart-account agents. |
| **Reusability & composability** | A backbone primitive every paying/earning agent reuses. |
| **Technical quality & completeness** | EIP-712 + EIP-1271, malleability-resistant ECDSA, reentrancy guard, no admin keys; 14 tests + invariants + fuzz + live stress. |
| **Security (CertiK Skill Scanner is the standard)** | Zero privileged roles; checks-effects-interactions; solvency invariant proven over 16,384 random ops. |
| **Deployment on Pharos** | Deployed + source-verified; full lifecycle exercised live. |
| **Docs & UX** | Complete Skill Engine package + runnable agent demo + validation report. |

## Scalability (measured)
`redeemMany` is linear at **~42k gas/voucher** (flat from 25→250 vouchers); a single `redeem`
is ~100k. At Pharos's ~2 Gigagas/s that's on the order of **~47k settlements/sec** (illustrative),
with off-chain voucher issuance effectively unbounded above that.

## Phase-2 vision
The included agent harness is the seed for a **Paywalled Data Agent**: an LLM agent that sells
API/data calls and gets paid per request via Quittance vouchers (HTTP 402 → voucher → `verify` →
serve → batched `redeem`). See `docs/PHASE2_PAYWALLED_DATA_AGENT.md`.

## Links
- Repo (main): https://github.com/Xyntera/Quittance
- Contract: https://atlantic.pharosscan.xyz/address/0xd872C6F530c2E1055a522B1978CA99FE65B99F56
- Skill entry point: [`SKILL.md`](SKILL.md) · Reference: [`references/quittance.md`](references/quittance.md)
- Validation & evidence: [`VALIDATION.md`](VALIDATION.md)
