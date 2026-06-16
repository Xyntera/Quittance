# PayRail — Skill Engine Validation

This document validates the PayRail skill against the
[Pharos Skill Engine guide](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide)
— both the required file format and the publishing checklist — and records live, on-chain
evidence that an agent can invoke it end-to-end.

## 1. Format compliance

### Folder layout (matches the Skill Engine package)
```
SKILL.md                       ✓ agent entry point + Capability Index
assets/networks.json           ✓ RPC URLs / chain ids / explorers
assets/tokens.json             ✓ token registry
assets/payrail/PayRail.sol     ✓ contract under assets/<skill>/
assets/templates/payrail.ts    ✓ off-chain interaction template
references/payrail.md          ✓ references/<skill>.md
src/payrail/PayRail.sol        ✓ source
script/payrail/DeployPayRail.s.sol
test/PayRail.t.sol
examples/agent/payrail-agent.mjs   (runnable invocation demo)
```

### SKILL.md — required sections (per the guide)
| Required section | Present |
|------------------|---------|
| Prerequisites | ✓ |
| Network Configuration | ✓ |
| Capability Index (`User Need | Capability | Detailed Instructions`) | ✓ (9 rows) |
| Write Operation Pre-checks | ✓ (4 checks) |
| General Error Handling | ✓ |
| Security Reminders | ✓ |

### references/payrail.md — required per-operation sections
Every operation documents: **Overview · Command Template · Parameters · Output Parsing ·
Error Handling (`Error Signature | Cause | Suggested Action`) · Agent Guidelines** — for
`deploy, deposit, sign-voucher, verify, redeem, redeemMany, withdraw, reads, verify-source`.

## 2. Publishing checklist

| Checklist item | Status |
|----------------|--------|
| Contract compiles (`forge build`) | ✓ |
| Test suite passes (`forge test`) | ✓ 14 tests incl. EIP-1271, replay/expiry/tamper, fuzz |
| Deployed on Pharos testnet (confirmed tx hash) | ✓ `0xdfDf119964C7858905FbE7175Ff32fdD509dEc50` |
| Contract verified on Pharos Scan | ✓ [verified](https://atlantic.pharosscan.xyz/address/0xdfDf119964C7858905FbE7175Ff32fdD509dEc50) |
| Reference file complete for every public function | ✓ |
| Capability Index updated with natural-language phrasings | ✓ |
| Revert strings match between contract and Error Handling tables | ✓ |

## 3. Live agent-invocation evidence

Run faithfully through the Skill Engine runtime flow (read `SKILL.md` → match Capability
Index → read `references/payrail.md` → read `networks.json` → run pre-checks → execute
`cast` → parse output) by [`examples/agent/payrail-agent.mjs`](examples/agent/payrail-agent.mjs)
against the live deployment on Pharos Atlantic Testnet (688689):

| Agent request (natural language) | On-chain result | Tx |
|----------------------------------|-----------------|----|
| "what is my PayRail balance?" | read `balanceOf` → parsed PHRS balance | (call) |
| "deposit 0.03 PHRS into PayRail" | `depositNative()` settled | `0x245da8752f5feff84fdb0745b3e495db52b374b4f39fba972c035342444d7d33` |
| "pay 0.004 PHRS to 0x…C0ffee00 for invoice-…" | off-chain EIP-712 sign → `verify → true "ok"` → `redeem` → payee paid, `nonceUsed=true` | `0x2954fb23b9be61a5105a6985cfed0e67a12d71b2426ac83da28d12c5e776f509` |
| Deploy | `PayRail` constructor | `0x60cbe8c80a53794c6c7d8bc56b96b36e1a643015e9d34c226aeddea45562afa3` |

Reproduce:
```bash
export PRIVATE_KEY=0xYOUR_TESTNET_KEY
node examples/agent/payrail-agent.mjs "deposit 0.03 PHRS into PayRail"
node examples/agent/payrail-agent.mjs "pay 0.004 PHRS to 0x00000000000000000000000000000000C0ffee00 for invoice-1"
```

## 4. Security self-review (CertiK Skill Scanner is the official standard)

- **No privileged roles** — no owner, admin, pause, upgrade, or fee setters; nothing to abuse or rug.
- **Reentrancy** — `nonReentrant` on every fund-moving entry point; checks-effects-interactions
  (nonce burned + balance debited *before* payout).
- **Signature safety** — EIP-712 domain bound to `chainId` + contract address; ECDSA rejects
  high-`s` (malleable) signatures and bad `v`; EIP-1271 for smart-account payers.
- **Replay** — single-use `nonceUsed[payer][nonce]`; timing bounded by `validAfter`/`validBefore`.
- **Token safety** — low-level transfer/transferFrom tolerant of non-standard (no-return) ERC20s;
  return data checked.
- **Funds isolation** — each payer can only ever spend/withdraw their own deposited balance.
