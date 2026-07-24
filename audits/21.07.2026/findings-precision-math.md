# Precision & Math Audit — `src/Executor.sol` (second pass)

**Scope**: Arithmetic and numeric-precision review only, before Base mainnet deploy.
**Commit context**: current `main` (`4aaed4f`). Target: Base mainnet (`8453`) / Base Sepolia (`84532`), EVM `cancun`, solc `0.8.36`.
**Focus**: the post-first-audit accounting change — `execute(target, data, value)` takes explicit `value`, and `bundleExecute` sums `values[i]` in a checked loop compared to `address(this).balance` at entry. That summed-values arithmetic was not covered by the first audit.
**Result**: **No precision/math vulnerabilities.** The new summed-values check is arithmetically sound. Two Info items record the analysis.

## [PM-1] Checked `totalValue` accumulation cannot silently wrap; overflow is a harmless owner-input revert
**Severity**: Info
**Category**: precision-math
**Location**: `bundleExecute()` — `src/Executor.sol:141-145`
**Description**: `totalValue += values[i]` runs under solc 0.8.36 default checked arithmetic (no `unchecked` anywhere), so a sum exceeding `type(uint256).max` reverts rather than wrapping. A silent wrap would let `totalValue` under-state the true sum and pass the `> balance` gate, authorizing a bundle that collectively over-spends. That is unreachable: the addition reverts. It is also not reachable with realistic values — a legitimate sum is bounded by the balance (bounded by ~1.2e26 wei ETH supply), ~50 orders of magnitude below `2^256`. Loop counter `++i` is checked and bounded by `values.length`. Confirms the first audit's conclusion holds under the new `> balance` comparison (vs old `!= msg.value`).
**Proof of Concept**: `values = [2^255, 2^255, 2^255]` → second `+=` reverts `Panic(0x11)`; no value moved, no state change. No input both wraps `totalValue` and proceeds to spend.
**Recommendation**: None. Do **not** wrap the accumulation in `unchecked` for gas — that would reintroduce a silent-wrap path on the one value-authorizing computation in the contract.

## [PM-2] Entry-balance snapshot vs per-leg spends and mid-bundle refunds — conservative and sound
**Severity**: Info
**Category**: precision-math
**Location**: `bundleExecute()` — `src/Executor.sol:141-153`; `execute()` — `src/Executor.sol:103-106`
**Description**: The bundle checks `totalValue <= address(this).balance` once at entry, then forwards each leg `values[i]`. Because the function is `payable`, the snapshot already includes fresh `msg.value` (fungible with stored ETH). Analysis of the interaction:
- Let `B` = entry balance, `S = totalValue = Σ values[i]`, with `S ≤ B` enforced. For every prefix `k`: `Σ_{i<k} values[i] ≤ S ≤ B`, so the balance before leg `k` is `≥ B − S + values[k] ≥ values[k]`. Every per-leg `call{value: values[i]}` is always solvent — no per-leg underflow, no leg-level revert from insufficient balance.
- Mid-bundle ETH inflows (a leg's target sending ETH back via `receive()`) only increase the running balance, strengthening the guarantee; they cannot break it.
- Deliberately conservative: a bundle can never be made affordable by relying on a mid-bundle refund, because the entry check compares full `totalValue` to the pre-execution balance and rejects up front — no "spend, get refunded, spend again" over-commit.
- Re-entrant drains during a bundle are blocked by the transient reentrancy guard (`locked`), so balance decreases only by forwarded `values[i]` — the accounting is exact.

Single-call `execute` uses the matching boundary: `value > balance` reverts, then spends `value`; strict `>` permits spending the full balance.
**Proof of Concept**: No failure mode. `B=10, values=[10,10]` → `20 > 10` reverts at entry even if leg 0 would refund mid-bundle. `B=10, values=[6,4]` → passes; both legs solvent.
**Recommendation**: None. Doc note (already in CLAUDE.md): excess `msg.value` beyond `totalValue` is not auto-refunded; it stays in the balance — intended custody choice, not a defect.

## Comparison-operator boundary review (checklist #26 / M-11)
All value-bearing comparisons verified correct (equal-balance spend allowed, over-spend rejected):
- `execute:103` — `value > balance` revert — spend up to full balance — correct
- `bundleExecute:145` — `totalValue > balance` revert — spend up to full balance — correct
- `withdrawEth:168` — `balance < amount` revert — withdraw full balance — correct
- `withdrawERC20:203` — `balanceOf < amount` revert — withdraw full token balance — correct

No `>`/`>=` or `<`/`<=` off-by-one affects fund movement.

## Verified sound
Full checklist walked. Entire arithmetic surface = one checked `uint256` accumulation (PM-1), ordered balance comparisons, and array-length/index bookkeeping. No division, multiplication, rounding, fixed-point, share/asset conversion, fee math, oracle/decimal scaling, downcast, signed arithmetic, `unchecked`, time arithmetic, exponentiation, or sentinel-max usage. N/A families: division-before-mult; rounding/inverse-fee; downcast/negative-cast/mixed-sign/time-narrow; oracle/token decimals/ERC4626 scaling/mixed-precision; accumulator/interest/reward math; assembly `div(x,0)` (only `_bubbleRevert`, a memory-safe bare `revert`, no division); `type(uint256).max` sentinel/exponentials/`uint24` time literals; negative-to-uint underflow (`totalValue` only `+=`, no subtraction on any path). First audit's conclusions re-confirmed under the new model.

---

**Summary count** — Critical: 0 · High: 0 · Medium: 0 · Low: 0 · Info: 2.
