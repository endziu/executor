# Findings — Weird ERC20 Tokens (second audit, pre-Base-mainnet)

**Scope:** `src/Executor.sol` (`withdrawERC20`, `_safeTransfer`, the `IERC20`
interface, the `execute()` escape hatch) · `foundry.toml`. Deployment targets Base
mainnet (`8453`) / Base Sepolia (`84532`), EVM `cancun`, solc `0.8.36`.

**Method:** walked the full weird-ERC20 checklist (34 items) against the current
code and diffed the token paths against the first-audit commit (`fd4e7ff`) plus its
remediation.

**Structural fact shaping every verdict (unchanged and re-verified):** the Executor
keeps **no internal token accounting** — no cached balances, no share/vault math, no
`totalSupply` pricing, no `decimals()`/`name()`/`symbol()` reads, no credited
deposit amounts. `withdrawERC20` reads `balanceOf(address(this))` live immediately
before each transfer. This neutralizes the entire value-corruption class
(fee-on-transfer, rebasing, high-decimal overflow, flash-mint, max-amount sentinel):
no stored number can drift from reality.

**What changed since the first audit (token-relevant):**
1. `execute` now takes an explicit `value` (breaking ABI change) and can fund calls
   from stored balance; the exact-`msg.value` model is gone. Token flows re-checked
   against this below.
2. `withdrawERC20` now rejects `amount == 0` with `ZeroAmount` (F-8 remediation),
   closing the zero-amount sub-case of the prior E-1.
3. The `withdrawERC20` NatSpec escape hatch was updated to the new 3-arg form
   `execute(token, abi.encodeCall(IERC20.transfer, (to, amount)), 0)`.

The strict `_safeTransfer` (F-4, accepted) and the blocklist/ERC777 items (E-2/E-3,
accepted) are **not re-reported** — the current code does not change their impact.
Their re-verification under the new model is recorded in "Verified sound".

---

## [E-1] `withdrawERC20` emits `ERC20Withdrawn` without confirming the balance moved
**Severity**: Info
**Category**: erc20
**Location**: `withdrawERC20()` / `_safeTransfer()` — `src/Executor.sol:195-207`, `:231-249`
**Description**: `_safeTransfer` treats an empty return (USDT-class no-return) and a
`bool`-`true` return as success, which is the correct OZ SafeERC20 semantics. It does
**not** read `balanceOf` after the call to confirm tokens actually moved. A
non-standard or malicious token that returns `true` (or no data) from `transfer` while
moving nothing would pass `_safeTransfer` and cause the contract to emit
`ERC20Withdrawn(token, amount, to)` even though no balance changed. No funds are lost
or locked and no third party is affected — the misleading signal reaches only the
owner (who chose to hold the token) and any off-chain tooling that trusts the event.
This is a best-practice observation, not a vulnerability; it is called out because a
second audit should have it on record. The prior audit folded it under "no internal
accounting / N/A".
**Proof of Concept**: Deploy a token whose `transfer(to,amount)` returns `true` but is
a no-op. Fund the Executor with a nonzero `balanceOf`. Call
`withdrawERC20(token, amount, to)` with `amount <= balanceOf`. The call succeeds and
emits `ERC20Withdrawn`, but `to`'s balance is unchanged. No revert, no loss — only a
false-positive event.
**Recommendation**: For a personal proxy this is optional hardening; do **not** add it
if it complicates fee-on-transfer/rebasing tokens (it would, by making the delivered
amount != requested amount revert). If desired, a balance-delta assertion documented as
"exact-transfer only" would surface a lying token:
```solidity
uint256 before = token.balanceOf(to);
_safeTransfer(erc20, to, amount);
// only valid for exact-transfer tokens; breaks fee-on-transfer/rebasing:
// if (token.balanceOf(to) - before != amount) revert ERC20TransferFailed();
```
Given the no-accounting design and the fee-on-transfer support this would sacrifice,
**accepting the current behavior is the reasonable call** — recorded here for
completeness, not as a required change.

---

## Verified sound

The ERC20 domain is clean at Medium and above. No new Critical/High/Medium issue was
introduced by the explicit-value model or is otherwise present.

**Explicit-value `execute` vs. token flows (the flagged concern) — sound.**
- The dedicated token path (`withdrawERC20` → `_safeTransfer`) attaches **no ETH** to
  the `transfer` call; it is a plain `address(token).call(data)` with no value. The
  accounting-model change does not touch it.
- The documented escape hatch passes an explicit `value` of `0`
  (`execute(token, transfer(to,amount), 0)`), so it calls `token.transfer` with zero
  value exactly as before; the NatSpec was correctly updated to the 3-arg form. The
  hatch still works: `data.length > 0` clears the `NoTransactionData` guard, the token
  has code so the `TargetNotContract` guard passes, and `value == 0` trivially clears
  the `InsufficientBalance` check.
- ETH-bearing token calls (`execute(token, transfer(...), value>0)`) are possible but
  only owner-initiated with owner-chosen inputs; a non-payable `transfer` reverts
  (recoverable, owner error), and no third-party funds are induced or at risk. No new
  token-flow hazard.

**Return-value handling — covered.** `_safeTransfer` accepts empty returndata (USDT
no-return, Ethereum), and for nonempty returndata requires `length >= 32` and
`decode==true`, rejecting short/dirty/`false` returns (Tether-Gold-class) as
`ERC20TransferFailed`. The `token.code.length == 0` guard (`:199`) rejects codeless
addresses, defending the Solmate silent-success case. Base-relevant note: native USDC
(Circle) and bridged USDbC on Base are standard `bool`-returning, 6-decimal tokens and
withdraw cleanly through `withdrawERC20`.

**Value-corruption class — N/A by design.** Fee-on-transfer, rebasing (incl. aTokens /
stETH-class), high-decimal overflow (>18 decimals), flash-mint totalSupply
manipulation, and the `type(uint256).max` "transfer-all" sentinel (cUSDCv3/Comet) have
no attack surface: no cached balances, no multiplication, no `totalSupply` pricing.
`withdrawERC20`'s `balanceOf(this) < amount` check even inadvertently blocks the
`type(uint256).max` sentinel (balance is always `< max`).

**Zero-amount transfers — fixed.** `withdrawERC20` now rejects `amount == 0`
(`ZeroAmount`, `:200`) before reaching `transfer`, so LEND/BNB zero-amount-revert
tokens no longer produce a confusing token-side revert on the dedicated path. Remaining
zero-amount needs (none expected) route through the escape hatch.

**Decimals / metadata — N/A.** The contract never reads `decimals()`, `name()`, or
`symbol()`, so decimal variance across chains, 0-decimal tokens, `decimals()`-on-zero
revert, and MKR-style `bytes32` metadata are all inapplicable.

**Approvals / permit — N/A.** No `approve`/`permit`/`transferFrom`/allowance surface
exists; USDT approve-race, BNB zero-approve, DAI non-standard permit, missing
`DOMAIN_SEPARATOR`, permit front-running, and infinite-approval drainage do not apply.

**Reentrant tokens (ERC777/ERC677) — contained.** Re-verified under the new model: all
four state-changing entry points share one `transient` `nonReentrant` lock held across
the entire outer call (including the whole `bundleExecute` loop), so a `tokensReceived`
/ `tokensToSend` / `transferAndCall` callback reverts with `ReentrancyGuard`. No
internal balances means no read-only-reentrancy surface.

**Blocklist / pause tokens (USDC/USDT) — accepted, unchanged.** An issuer blocklisting
the Executor's address or pausing transfers freezes the held balance token-side; no
in-contract mitigation exists and the escape hatch cannot bypass it (enforced against
the holding address). Inherent counterparty risk, unchanged by the new model.

**Multiple-address / native-ERC20-wrapper tokens — N/A.** No token registry or
per-token accounting, so same-underlying-multiple-address confusion and
native-currency ERC20-wrapper double-spend (CELO/POL/zkSync-style; not a Base concern)
do not apply.

---

## Summary

Critical 0 · High 0 · Medium 0 · Low 0 · Info 1 (E-1). No new Medium+ ERC20 issue; the
explicit-value model does not affect token flows, and the prior accepted items (F-4
strict `_safeTransfer`, E-2 blocklist, E-3 ERC777) are unchanged in impact.
