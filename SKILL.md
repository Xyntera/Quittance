---
name: payrail
title: PayRail — On-Chain Agent Micropayment Settlement (x402-style)
description: >-
  A credibly-neutral settlement layer for AI-agent payments on Pharos. A payer deposits
  funds (native PHRS or any ERC20 stablecoin), signs off-chain EIP-712 payment vouchers
  (no gas, no API key), and anyone — a relayer or x402 facilitator — settles them on-chain
  to the payee with single-use replay protection. Supports EOA and smart-account (EIP-1271)
  payers. No owner, no admin keys, no protocol fee. The payments backbone Phase-2 Agents
  build on.
network: pharos_atlantic_testnet
chainId: 688689
deployedAddress: "0xdfDf119964C7858905FbE7175Ff32fdD509dEc50"
verified: true
version: 0.1.0
license: MIT
---

# PayRail Skill

PayRail is the on-chain core of an [x402](https://www.x402.org)-style payment flow — *sign
off-chain, settle on-chain* — for the Pharos AI Agent economy. It turns "pay another agent /
a paid API per call" into one safe, reusable settlement primitive any Phase-2 Agent can
depend on.

**Flow:** `deposit` (payer funds) → sign an **EIP-712 voucher** off-chain → `verify` (server
pre-check) → `redeem` (anyone relays; payee gets paid). Single-use nonces prevent replay.

- **Live & verified:** [`0xdfDf119964C7858905FbE7175Ff32fdD509dEc50`](https://atlantic.pharosscan.xyz/address/0xdfDf119964C7858905FbE7175Ff32fdD509dEc50) on Pharos Atlantic Testnet (688689).
- Contract: `src/payrail/PayRail.sol` (mirror in `assets/payrail/PayRail.sol`)
- Deploy script: `script/payrail/DeployPayRail.s.sol`
- Full operation reference: [`references/payrail.md`](references/payrail.md)
- Network config: `assets/networks.json` · Tokens: `assets/tokens.json`
- Off-chain template (viem): `assets/templates/payrail.ts`
- Runnable agent-invocation demo: [`examples/agent/payrail-agent.mjs`](examples/agent/payrail-agent.mjs)

## Prerequisites

- **Foundry** (`cast`, `forge`) installed: `curl -L https://foundry.paradigm.xyz | bash && foundryup`.
- A **funded testnet account** — the signer needs PHRS for gas. Faucet: https://testnet.pharosnetwork.xyz
- The deployed **PayRail address** (above) or your own deploy (see references → "Deploy PayRail").
- Export `PRIVATE_KEY` (testnet only). It is passed explicitly to every write command; PayRail
  never reads it implicitly.

## Network Configuration

Read from [`assets/networks.json`](assets/networks.json). Default target:

| Field | Value |
|-------|-------|
| Network | Pharos Atlantic Testnet |
| chainId | `688689` |
| RPC | `https://atlantic.dplabs-internal.com` |
| Explorer | `https://atlantic.pharosscan.xyz` |
| Native coin | PHRS |

```bash
export RPC=https://atlantic.dplabs-internal.com
export RAIL=0xdfDf119964C7858905FbE7175Ff32fdD509dEc50
export ZERO=0x0000000000000000000000000000000000000000
```
The same package also lists **Pharos Testnet (`688688`, `https://testnet.dplabs-internal.com`)**;
deploy there unchanged and swap `--rpc-url` to target it.

## Capability Index

| User Need | Capability | Detailed Instructions |
|-----------|------------|-----------------------|
| "Deploy the payment rail / set up agent payments" | `forge script` deploy | → [references/payrail.md](references/payrail.md#deploy-payrail) |
| "Fund my agent / deposit PHRS or stablecoin to pay with" | `depositNative` / `deposit` | → [references/payrail.md](references/payrail.md#deposit-funds) |
| "Authorize a payment / sign a voucher to pay an agent or API" | `hashAuthorization` + sign | → [references/payrail.md](references/payrail.md#build--sign-a-voucher-off-chain-no-gas) |
| "Check a payment is good before delivering the resource" | `verify` | → [references/payrail.md](references/payrail.md#verify-read-only-x402-check) |
| "Settle / claim a payment / redeem a voucher" | `redeem` | → [references/payrail.md](references/payrail.md#redeem-settle-a-voucher) |
| "Settle many micropayments at once" | `redeemMany` | → [references/payrail.md](references/payrail.md#batch-settlement) |
| "Withdraw my unspent funds" | `withdraw` | → [references/payrail.md](references/payrail.md#withdraw-unspent-balance) |
| "Check balance / has a voucher been used" | `balanceOf` / `nonceUsed` | → [references/payrail.md](references/payrail.md#reads) |
| "Audit / verify the contract on the explorer" | `forge verify-contract` | → [references/payrail.md](references/payrail.md#verify-the-contract-on-pharosscan-optional) |

## Write Operation Pre-checks

Before executing any **write** (`deposit`, `withdraw`, `redeem`, `redeemMany`), the agent MUST:

1. **Confirm the network** — `cast chain-id --rpc-url $RPC` equals the `chainId` in `networks.json`.
2. **Confirm the contract** — `$RAIL` is the intended PayRail address (and is verified on the explorer).
3. **Confirm the signer & gas** — `cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $RPC` is `> 0`.
4. **Confirm the parameters** — echo the human-readable amount, token, payee and nonce back to the
   user and ensure, for `redeem`, that `verify(...)` returns `(true, "ok")` first.

## General Error Handling

- Reverts surface as human-readable strings prefixed `PayRail: ...` — read them directly; the
  per-operation **Error Handling** tables in [`references/payrail.md`](references/payrail.md) map
  each one to a cause and a suggested action.
- `PayRail: nonce already used` → the voucher was already redeemed; issue a new voucher with a
  fresh `nonce`.
- `PayRail: insufficient payer balance` → the payer must `deposit` more before the voucher settles.
- `PayRail: invalid signature` → the tuple was changed after signing, or the wrong key signed;
  re-`hashAuthorization` the exact tuple and re-sign with the payer key.
- RPC/network errors → retry; confirm the RPC URL and chain id from `networks.json`.

## Security Reminders

- **Never paste a mainnet/real private key.** Use a dedicated **testnet** key; it is only ever
  passed explicitly to `cast`/`forge`.
- PayRail has **no owner, no admin keys, no protocol fee** — nothing privileged to abuse.
- Funds are debited from the payer's balance **before** payout (checks-effects-interactions) under
  a reentrancy guard; ECDSA recovery rejects malleable signatures; smart-account payers use EIP-1271.
- A `nonce` is **single-use per payer** — treat it as the payment's idempotency key and never reuse it.
- Always `verify` before delivering a paid resource; confirm `nonceUsed` after `redeem`.

## Quick facts for the agent

- Voucher tuple: `(payer, payee, token, amount, nonce, validAfter, validBefore)`.
- `token = 0x0000000000000000000000000000000000000000` → native PHRS.
- `validBefore = 0` → never expires; `validAfter = 0` → valid immediately.
- Amounts are in wei: `cast to-wei <n> ether`; nonces: `cast keccak "<resourceId>"`.
- Settlement is gasless for the payer: any relayer/facilitator can submit `redeem`.
