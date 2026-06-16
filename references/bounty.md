# Skill Reference: `bounty` — Agent Task-Bounty Escrow

On-chain escrow for agent-to-agent task markets on Pharos. A poster escrows a reward
(native **PHRS** or any **ERC20**, e.g. PROS), workers submit deliverable pointers, and the
poster approves one worker to release payment — or cancels/reclaims to get a refund.

**Contract:** `BountyBoard` · **Skill id:** `bounty`

## Environment

```bash
# Live deployment (Pharos Atlantic Testnet, chain id 688689):
export RPC=https://atlantic.dplabs-internal.com         # the RPC the Skill Engine guide uses
export BOARD=0xa71e7baB1cB82F1Ee67ca6A32aEBD47840C922aA # verified BountyBoard
export PRIVATE_KEY=0xYOUR_TESTNET_KEY                    # must hold PHRS for gas
export DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)

# To use Pharos Testnet (chain id 688688) instead, deploy your own copy and set:
#   export RPC=https://testnet.dplabs-internal.com ; export BOARD=<your-deployed-address>
```

Status enum returned by views: `0 None`, `1 Open`, `2 Paid`, `3 Refunded`.

> **Agent Guidelines (global):** PHRS amounts are in wei — use `cast to-wei <n> ether`.
> Native rewards use `token = 0x0000000000000000000000000000000000000000`. For ERC20
> rewards you MUST `approve` the board for `amount` before `postBounty`. Always read the
> emitted event / view to confirm a write landed before telling the user it is done.

---

## Deploy BountyBoard

### Overview
Deploy the skill contract once per network. Reuse the same address for all bounties.

### Command Template
```bash
forge script script/bounty/DeployBountyBoard.s.sol \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
```

### Output Parsing
The script logs `BountyBoard deployed at: 0x...`. Save that as `$BOARD`. The deployed
address is also in `broadcast/DeployBountyBoard.s.sol/688688/run-latest.json`.

> **Agent Guidelines:** 1) Ensure `$PRIVATE_KEY` is funded with PHRS. 2) Run the script.
> 3) Capture the logged address into `$BOARD`. 4) Verify on the explorer (next section).

---

## Post a bounty (native PHRS)

### Overview
Escrow a native PHRS reward for a task. Returns a 1-based bounty `id`.

### Command Template
```bash
cast send $BOARD \
  "postBounty(address,uint256,uint64,string)" \
  0x0000000000000000000000000000000000000000 \
  $(cast to-wei 1 ether) \
  0 \
  "ipfs://<task-cid>" \
  --value $(cast to-wei 1 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Name        | Type      | Required | Description |
|-------------|-----------|----------|-------------|
| token       | `address` | yes      | `0x0` for native PHRS reward. |
| amount      | `uint256` | yes      | Reward in wei. Must be `> 0` and equal `--value`. |
| deadline    | `uint64`  | yes      | Unix seconds; `0` = no deadline. If set, must be in the future. |
| metadataURI | `string`  | yes      | Task description pointer (IPFS CID / URL / inline text). |
| `--value`   | flag      | yes      | Native amount to escrow; must equal `amount`. |

### Output Parsing
On success a `BountyPosted(id, poster, token, reward, deadline, metadataURI)` event is
emitted. Read the new id with `cast call $BOARD "bountyCount()(uint256)" --rpc-url $RPC`
(the latest post is `bountyCount`).

### Error Handling
| Revert string | Cause | Suggested action |
|---------------|-------|------------------|
| `BountyBoard: amount must be greater than zero` | amount = 0 | Pass a positive amount. |
| `BountyBoard: msg.value must equal amount for native reward` | `--value` ≠ amount | Make `--value` equal `amount`. |
| `BountyBoard: deadline already passed` | deadline ≤ now | Use `0` or a future timestamp. |

> **Agent Guidelines:** 1) Convert the human amount to wei. 2) Set `token` to `0x0` and
> `--value` to the same wei amount. 3) Send. 4) Read `bountyCount()` to learn the new id.

---

## Post a bounty (ERC20, e.g. PROS)

### Overview
Escrow an ERC20 reward. Requires a prior `approve` to let the board pull the tokens.

### Command Template
```bash
# 1) approve the board to pull the reward
cast send $TOKEN "approve(address,uint256)" $BOARD $(cast to-wei 100 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
# 2) post the bounty (no --value for ERC20)
cast send $BOARD "postBounty(address,uint256,uint64,string)" \
  $TOKEN $(cast to-wei 100 ether) 0 "ipfs://<task-cid>" \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Name    | Type      | Required | Description |
|---------|-----------|----------|-------------|
| token   | `address` | yes      | ERC20 token address (set `$TOKEN`). |
| amount  | `uint256` | yes      | Reward in token base units. Must be approved first. |
| deadline| `uint64`  | yes      | `0` = none, else a future Unix timestamp. |

### Error Handling
| Revert string | Cause | Suggested action |
|---------------|-------|------------------|
| `BountyBoard: do not send native value for ERC20 reward` | `--value` sent | Omit `--value`. |
| `BountyBoard: ERC20 transferFrom failed` | missing/short approval or balance | Approve `amount` and ensure balance. |

> **Agent Guidelines:** 1) `approve` the board for at least `amount`. 2) Call `postBounty`
> with the token address and NO `--value`. 3) Confirm via `getBounty`.

---

## Submit work

### Overview
A worker records a submission for an open bounty. The deliverable lives off-chain at `resultURI`.

### Command Template
```bash
cast send $BOARD "submitWork(uint256,string)" $ID "ipfs://<result-cid>" \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Name      | Type      | Required | Description |
|-----------|-----------|----------|-------------|
| id        | `uint256` | yes      | Bounty id. |
| resultURI | `string`  | yes      | Pointer to the deliverable. |

### Output Parsing
Emits `WorkSubmitted(id, worker, resultURI)`. Confirm with
`cast call $BOARD "hasSubmitted(uint256,address)(bool)" $ID $DEPLOYER --rpc-url $RPC`.

### Error Handling
| Revert string | Cause | Suggested action |
|---------------|-------|------------------|
| `BountyBoard: bounty is not open` | already paid/refunded or unknown id | Pick an open bounty. |
| `BountyBoard: deadline has passed` | past deadline | Too late; pick another bounty. |
| `BountyBoard: poster cannot submit to own bounty` | poster == caller | Submit from a different account. |

> **Agent Guidelines:** 1) Check `isOpen(id)` and `timeLeft(id)` first. 2) Submit the
> result pointer. 3) Confirm with `hasSubmitted(id, you)`.

---

## Approve a winner (release reward)

### Overview
The poster pays exactly one worker; the escrow is released atomically and the bounty closes.

### Command Template
```bash
cast send $BOARD "approve(uint256,address)" $ID $WINNER \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Name   | Type      | Required | Description |
|--------|-----------|----------|-------------|
| id     | `uint256` | yes      | Bounty id. |
| winner | `address` | yes      | Worker to pay; must have submitted. |

### Output Parsing
Emits `BountyApproved(id, winner, token, reward)`. `statusOf(id)` becomes `2 (Paid)`.

### Error Handling
| Revert string | Cause | Suggested action |
|---------------|-------|------------------|
| `BountyBoard: caller is not the poster` | not the poster | Call from the poster account. |
| `BountyBoard: winner has not submitted` | winner never submitted | Approve only a real submitter. |
| `BountyBoard: bounty is not open` | already settled | Nothing to do. |

> **Agent Guidelines:** 1) Confirm `hasSubmitted(id, winner)`. 2) Approve. 3) Verify
> `statusOf(id) == 2`.

---

## Cancel (no submissions) / Reclaim (after deadline)

### Overview
Recover the escrow. `cancel` works only while there are **zero** submissions (so no worker
who delivered is rug-pulled). `reclaim` works once a non-zero `deadline` has passed, even if
submissions exist (poster failed to approve in time).

### Command Template
```bash
cast send $BOARD "cancel(uint256)"  $ID --rpc-url $RPC --private-key $PRIVATE_KEY
cast send $BOARD "reclaim(uint256)" $ID --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Error Handling
| Revert string | Cause | Suggested action |
|---------------|-------|------------------|
| `BountyBoard: cannot cancel after a submission; use reclaim after deadline` | submissions exist | Use `reclaim` after the deadline. |
| `BountyBoard: deadline has not passed` | reclaim too early | Wait until `timeLeft(id) == 0`. |
| `BountyBoard: caller is not the poster` | not the poster | Call from the poster account. |

> **Agent Guidelines:** 1) If `submissionCount == 0`, use `cancel`. 2) Otherwise wait for
> the deadline then `reclaim`. 3) Verify `statusOf(id) == 3 (Refunded)`.

---

## Read bounty state (view)

### Command Template
```bash
cast call $BOARD "getBounty(uint256)(address,address,uint256,uint64,uint64,uint32,uint8,address,string)" $ID --rpc-url $RPC
cast call $BOARD "isOpen(uint256)(bool)"     $ID --rpc-url $RPC
cast call $BOARD "timeLeft(uint256)(uint256)" $ID --rpc-url $RPC
cast call $BOARD "statusOf(uint256)(uint8)"  $ID --rpc-url $RPC
cast call $BOARD "bountyCount()(uint256)"    --rpc-url $RPC
```

### Output Parsing
`getBounty` returns, in order: `poster, token, reward(wei), createdAt, deadline,
submissionCount, status(0..3), winner, metadataURI`. `token == 0x0` means native PHRS.

> **Agent Guidelines:** Always read state before acting. Use `statusOf` to branch:
> `1` → can submit/approve/cancel/reclaim; `2`/`3` → settled, no further action.

---

## Verify the contract on PharosScan (optional)

```bash
forge verify-contract $BOARD src/bounty/BountyBoard.sol:BountyBoard \
  --verifier blockscout \
  --verifier-url https://api.socialscan.io/pharos-testnet/v1/explorer/command_api/contract \
  --chain-id 688688
```

> **Agent Guidelines:** Verification makes the source readable on the explorer so users
> and other agents can audit the skill before trusting it with funds.
