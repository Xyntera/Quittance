# Phase 2 Spec — Paywalled Data Agent (on Quittance)

> Agent Arena (Phase 2) concept that composes the Phase-1 **Quittance** skill into a complete,
> revenue-earning on-chain Agent. Status: design.

## Goal
Ship an autonomous **Paywalled Data Agent**: an LLM agent that exposes a useful endpoint
(data / inference / search) and **charges per request**, settling payments through Quittance —
the on-chain version of x402's "402 → pay → serve". It demonstrates an Agent that *operates,
transacts, and earns* on Pharos.

## Actors
- **Provider Agent** (what we build) — serves a paid resource; prices each request; verifies and
  settles payments via Quittance.
- **Client Agent** — wants the resource; holds a Quittance deposit; signs vouchers to pay.
- **Quittance** (Phase-1 skill, already live) — escrow + voucher verification + settlement.
- **Facilitator/Relayer** — submits `redeem`/`redeemMany` on-chain (can be the Provider itself).

## Request flow (HTTP 402, x402-style)
```
Client Agent → GET /resource
Provider Agent → 402 Payment Required
                 { payTo, token, amount, nonce, validBefore, quittance, chainId }   (the price quote)
Client Agent → signs an EIP-712 Quittance voucher for that quote (off-chain, no gas)
Client Agent → GET /resource   +  X-PAYMENT: <voucher+signature>
Provider Agent → quittance.verify(voucher) == (true,"ok") ?
                 → yes: serve the resource, queue the voucher
Provider Agent (batch loop) → quittance.redeemMany([vouchers]) every N seconds / M vouchers
```

## What's reused from Phase 1 (no new contract needed)
- `verify(auth,sig)` — the Provider's pre-serve check.
- `redeem` / `redeemMany` — settlement (batched for economy; we measured ~42k gas/voucher).
- `hashAuthorization` / `DOMAIN_SEPARATOR` — voucher construction.
- `balanceOf` / `nonceUsed` — client funding + idempotency checks.
- The deployed, verified contract `0xd872C6F530c2E1055a522B1978CA99FE65B99F56`.

## What's new in Phase 2 (the Agent)
1. **Provider service** — an HTTP server that issues 402 quotes, verifies vouchers, serves the
   resource, and runs a **batched settlement loop** (collect vouchers → `redeemMany`).
2. **Client agent (LLM)** — given a task, discovers the price from the 402, decides whether to pay
   (budget/policy), signs the voucher, retries with `X-PAYMENT`. This is the Phase-1
   `examples/agent/quittance-agent.mjs` harness with its router swapped for an LLM + an HTTP layer.
3. **Pricing & metering** — per-endpoint price, optional dynamic pricing.
4. **(Optional) facilitator** — a standalone relayer that batches redeems for many providers.

## Milestones
- **M1 — Provider MVP:** 402 quote + `verify` gate + serve. Single resource (e.g. a price feed).
- **M2 — Settlement loop:** queue vouchers, `redeemMany` on a timer; dashboard of revenue.
- **M3 — LLM client agent:** natural-language task → discover price → pay → consume.
- **M4 — Multi-endpoint + dynamic pricing;** optional standalone facilitator.
- **M5 — Demo + docs:** end-to-end recorded run on Pharos testnet.

## Demo plan
A client agent is told *"get me the ETH/USD price"*; it hits the provider, receives a 402, signs a
Quittance voucher, retries, gets the data; the provider batches the day's vouchers into one
`redeemMany`. Show the provider's on-chain revenue growing per request.

## Risks & mitigations
- **Voucher under/non-payment** → Provider always `verify`s before serving; only serves if
  `(true,"ok")`; settles promptly to avoid client withdrawing the deposit first.
- **Client withdraws deposit before settle** → keep settlement latency low (batch every few
  seconds), or (stretch) add a short hold/commit; or require the client's balance ≥ outstanding.
- **Streaming/very-high volume** → adopt the netting/channel upgrade (cumulative per-pair counter)
  noted in `VALIDATION.md` so N requests = O(1) storage and one settle.
- **Replay/double-serve** → nonce = resource id; Provider also de-dups on `nonceUsed`.

## Why this is a strong Phase-2 entry
It turns a Phase-1 *primitive* into a *working business*: an agent that earns real on-chain
revenue per call — exactly the "agents that operate, transact, and interact on-chain" the Agent
Arena asks for — while reusing a deployed, audited-style settlement skill.
