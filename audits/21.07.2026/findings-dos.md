# Findings — DoS & Gas Griefing (second pass, pre-Base-mainnet)

**Scope of this pass.** Re-audit of `src/Executor.sol` after the ETH-accounting
change: `execute(target, data, value)` now takes an **explicit** `value`,
`bundleExecute` checks `sum(values)` against `address(this).balance` **at entry**,
stored ETH and fresh `msg.value` are fungible, and `receive()` accepts deposits
from **anyone**. The prior DoS pass (`findings-dos.md`, 20.07) rated everything
Info because every mutating entry point is `onlyOwner`; F-7 (owner-self-inflicted
gas/returndata/revert vectors) is **ACCEPTED as out of the threat model**.

**This pass therefore only looks for NEW DoS surface**: (a) anything a
*non-owner* can now reach through the deposit path or a mid-bundle balance change,
(b) any way the transient reentrancy guard can wedge a legitimate multi-call
pattern, and (c) any change to the recovery guarantees F-7 relied on. **None was
found.** The new model is strictly more robust against griefing than the old
exact-`msg.value` model, because the only unauthenticated state change a third
party can cause is *increasing* the balance, which can never fail an
`InsufficientBalance` check.

**Result:** Critical 0, High 0, Medium 0, Low 0, Info 2.

---

## [D-1] Third-party deposits and mid-bundle balance changes cannot wedge execution
**Severity**: Info
**Category**: dos
**Location**: `execute()` `src/Executor.sol:103`; `bundleExecute()` `src/Executor.sol:141-153`; `receive()` `src/Executor.sol:264`
**Description**: The new model lets anyone add ETH via `receive()`, and funds calls from the pooled balance. The concern is whether a third party can manipulate `address(this).balance` to force an owner transaction to revert (griefing), or whether a mid-bundle balance change can strand a later leg. Analysis shows neither is possible:
- **Deposits only raise the balance.** Both guards are one-directional: `execute` reverts only when `value > address(this).balance` (`:103`) and `bundleExecute` only when `totalValue > address(this).balance` (`:145`). A third-party `receive()` deposit can only *increase* the balance, so it can only make these checks *more* likely to pass. There is no non-owner code path that *reduces* the balance (all withdrawals/execute are `onlyOwner`), so a front-runner cannot drive the balance below what an owner tx requires. The old exact-`msg.value` model was actually more brittle here (a stale `msg.value` mismatch); the pooled model removes that.
- **Mid-bundle balance is monotone-safe.** The entry check guarantees `sum(values) <= balance`. Each leg spends exactly `values[i]` (`:151`), and nothing can drain the balance mid-loop: the only way to move the Executor's ETH out is to re-enter a guarded function, which is blocked by the transient guard (`locked == true` for the whole `bundleExecute` body). Any ETH a leg's target sends *back* into the Executor lands in the unguarded `receive()` and only raises the balance. Therefore every per-leg `call{value: values[i]}` always has sufficient balance and can never fail for balance reasons — a failed leg can only come from the target itself reverting (owner-chosen target → F-7, accepted).
**Proof of Concept**: No failure mode. Attempted griefs: (1) attacker front-runs `execute`/`bundleExecute` with a `receive()` deposit → balance rises, owner tx still succeeds. (2) attacker tries to lower the balance before the owner's tx → no non-owner path exists. (3) a bundle leg returns ETH to the Executor mid-loop → `receive()` (unguarded) accepts it, balance rises, subsequent legs unaffected.
**Recommendation**: None. This is a positive control; documented here so the new-model reasoning is on record. Keep `receive()` **unguarded** — adding a `nonReentrant` guard to `receive()` would break legitimate bundles whose legs route ETH back through the Executor, converting a safe pattern into a revert.

## [D-2] `execute` now bubbles adversarial returndata — bounded, owner-only, no new reach
**Severity**: Info
**Category**: dos
**Location**: `execute()` `src/Executor.sol:106-113`; `_bubbleRevert()` `src/Executor.sol:256-262`
**Description**: F-8 changed `execute` to surface a failing target's revert reason via `_bubbleRevert(result)` (`:111`) instead of swallowing it. A malicious target can revert with a large returndata "bomb": the `.call` at `:106` copies the full returndata into the `result` buffer (memory expansion), and `_bubbleRevert` then re-reverts that exact buffer (`revert(add(32, returndata), mload(returndata))`, `:259`). This is a genuine gas-amplification primitive, but it changes nothing in the threat model: `execute` is `onlyOwner`, the target is owner-chosen, the whole tx reverts and unwinds, and the gas is owner-paid. It is the same F-7-accepted "owner-self-inflicted returndata copy" primitive, now with a re-revert of already-copied data — it does **not** become non-owner-reachable and removes **no** recovery path (the owner simply avoids/retries without that target). `bundleExecute` remains immune: its leg call discards returndata (`(bool success,)` at `:151`), so no leg can bomb the batch, and it raises `ExecutionFailed(i)` rather than bubbling.
**Proof of Concept**: Owner calls `execute(evilTarget, data, value)`; `evilTarget` reverts returning ~megabytes of data. `result` is expanded to hold it, `_bubbleRevert` re-reverts it, the owner's tx runs out of gas / reverts. No third party is involved and nothing is bricked.
**Recommendation**: Accept as-is (consistent with the F-7 disposition). If a hard bound is ever wanted purely for owner ergonomics, cap the bubbled length, e.g.:

    if (!success) {
        uint256 n = result.length < 256 ? result.length : 256; // cap bubbled bytes
        assembly ("memory-safe") { revert(add(result, 32), n) }
        // (unreachable) revert ExecutionFailed(0);
    }

Not required for security — no third-party impact.

---

## Verified sound (checklist areas clean)

- **Reentrancy-guard permanent brick — SOUND.** `locked` is `bool private transient` (EIP-1153, `:19`). `_nonReentrantBefore` sets it (`:52`), `_nonReentrantAfter` clears it (`:56`). Even though the clear runs *after* the external call, transient storage is discarded at end-of-transaction, so a bubbled revert or an OOG in the guarded body can never persist `locked = true` into a later tx. The guard cannot be permanently wedged.
- **Transient guard vs. multi-call in one tx — SOUND (confirmed).** Concern: an owner batching several Executor calls through a multicall/Safe in a single tx, where transient storage lives for the whole tx. Because `_nonReentrantAfter` clears `locked` at the end of each *top-level* Executor call, sequential top-level calls in one tx each see `locked == false` on entry and succeed. Only genuinely *nested* re-entry (a target calling back into a guarded function while the outer call is still on the stack) is blocked — the intended behavior. Legitimate sequential batching is unaffected.
- **New balance model — SOUND (see D-1).** Deposits are monotone-increasing and third-party-only-upward; no non-owner balance-reduction path; mid-bundle balance is always sufficient given the entry sum check plus the reentrancy guard preventing mid-loop drains.
- **Returndata bombing in `bundleExecute` — IMMUNE.** Leg return value discarded (`:151`); no copy, no re-revert. Batch path cannot be bombed by any leg.
- **Insufficient gas forwarding (SWC-126) — SOUND.** No `.call{gas: X}()` with a fixed amount anywhere; all external calls forward remaining gas.
- **Try/catch griefing — N/A.** No `try/catch`; low-level `call` with explicit `success` checks, no forceable catch branch.
- **Unbounded loops / L2 array-filling — owner-bounded.** The `sum(values)` loop (`:142-144`) and the exec loop (`:147-153`) iterate only over `onlyOwner` calldata arrays; no attacker-growable persistent state. A too-large bundle reverts the owner's own atomic tx. On Base the practical cap is the block gas limit; still owner-self-inflicted (F-7, accepted).
- **External calls inside a loop / blocklisted-recipient batch — atomic by design.** A bundle leg to a blocklisted/reverting recipient reverts the whole bundle (`ExecutionFailed(i)`, `:152`). Recipients/targets are owner-chosen; atomic-all-or-nothing is the documented design. No shared/third-party queue to brick.
- **ETH receiver with reverting fallback — owner-chosen, recoverable.** `withdrawEth` (`:170`) and `execute`/bundle legs revert if an owner-chosen recipient rejects ETH; the owner retries with an accepting address. No stored beneficiary, no lock.
- **Zero-amount transfer reverts — hardened.** `withdrawEth`/`withdrawERC20` now reject `amount == 0` (`ZeroAmount`, `:167`/`:200`) per the F-8 fix; a zero-amount leg to a zero-revert token via `execute` is owner-chosen.
- **`balanceOf()` reverting causes DoS — recoverable.** `withdrawERC20` reads `balanceOf` unguarded (`:203`); a reverting token blocks that path but the owner sweeps via `execute(token, transfer(to, amount), 0)`, which never touches `balanceOf`. F-7, accepted; escape hatch intact.
- **Overflow-revert DoS — SOUND.** `totalValue += values[i]` (`:143`) is checked arithmetic under 0.8.36; an overflowing bundle reverts the owner's own tx.
- **Block stuffing / timelock / economic griefing / paymaster / oracle / pause-brick — N/A.** No time-sensitive actions, timelocks, liquidations, paymasters, oracles, or pause mechanism exist in scope.

## Summary
Critical 0, High 0, Medium 0, Low 0, Info 2. No new non-owner-reachable DoS or brick vector is introduced by the explicit-value accounting model; third-party deposits and mid-bundle balance changes cannot wedge execution, the transient guard is confirmed safe across sequential multi-call batching, and `execute`'s new returndata bubbling stays owner-bounded with all F-7 recovery paths intact.
