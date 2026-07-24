# Precision & Math Audit — `src/Executor.sol`

> **Post-audit accounting change:** This historical review describes commit
> `fd4e7ff`. The checked bundle sum is now compared to the Executor's available
> balance rather than required to equal fresh `msg.value`. Checked-overflow
> behavior is unchanged and is covered by a regression test.

**Scope**: Arithmetic and numeric-precision review only.
**Result**: No precision/math findings. The contract performs one arithmetic
operation (a checked `uint256` accumulation) and one exact-equality comparison.
There is no division, rounding, fixed-point, share/asset conversion, downcasting,
or `unchecked` code anywhere in the contract.

---

## Arithmetic surface

The entire numeric surface of the contract is in `bundleExecute`
(`src/Executor.sol:131-135`):

```solidity
uint256 totalValue = 0;
for (uint256 i = 0; i < values.length; ++i) {
    totalValue += values[i];
}
if (totalValue != msg.value) revert IncorrectEthValue();
```

- `totalValue` is `uint256`; each `values[i]` is `uint256`.
- The addition executes under Solidity 0.8.36 default **checked** arithmetic
  (no `unchecked` block), so any overflow reverts rather than wrapping.
- The loop counter `++i` is also under checked arithmetic; bounded by
  `values.length`, it cannot overflow.
- The comparison is exact equality (`!=`), not an ordered comparison, so there
  is no `>`/`>=` boundary ambiguity.

Overflow of the sum is not reachable in practice: `msg.value` is bounded by the
total ETH supply (~1.2e26 wei), which is ~50 orders of magnitude below
`type(uint256).max` (~1.15e77). Even a maliciously crafted `values[]` array that
summed past `2^256` would trigger a checked-arithmetic revert (a harmless DoS on
an input the caller controls and pays for), never a silent wrap that could
desync `totalValue` from `msg.value`. The equality check `totalValue == msg.value`
is therefore sound.

The remaining "math" in the contract is index/length bookkeeping
(`targets.length != data.length`, array indexing, `keccak256`, `.code.length`,
`.balance` comparisons) — comparisons and reads, not arithmetic that can lose
precision.

---

## Checklist coverage

Walked against the evm-audit-precision-math checklist. Every item is N/A; reasons:

| # | Item | Status | Reason |
|---|------|--------|--------|
| 1 | Division before multiplication | N/A | No division anywhere. |
| 2 | Hidden div-before-mul in `mulDiv`/`wmul`/`wdiv` | N/A | No such libraries/calls. |
| 3 | Extra divisions by scaling factor | N/A | No scaling factors. |
| 4 | Division → zero for small values | N/A | No division. |
| 5 | Protocol-favoring rounding (deposit down / withdraw up) | N/A | No rounding; not a vault. |
| 6 | Inconsistent rounding across functions | N/A | No rounding. |
| 7 | Inverse fee `assets/(1-fee)` | N/A | No fees. |
| 8 | Overflow in `unchecked` blocks | N/A | No `unchecked` blocks in the contract. |
| 9 | Downcast overflow (`uint256`→`uint128/64/32`) | N/A | No downcasts; all values are `uint256`. |
| 10 | Negative-to-unsigned cast | N/A | No signed integers used. |
| 11 | Signed/unsigned add/sub overflow | N/A | No signed integers. |
| 12 | Overflow in time-based calc | N/A | No time/`block.timestamp` arithmetic. |
| 13 | Oracle decimal mismatch | N/A | No oracles. |
| 14 | Token decimal mismatch in pricing | N/A | No price calculations; raw token amounts only. |
| 15 | ERC4626 non-18-decimal scaling | N/A | Not a vault; no share math. |
| 16 | Zero/one wei remaining after division | N/A | No division. |
| 17 | Compounding vs simple interest | N/A | No interest accrual. |
| 18 | Reward-per-token precision loss | N/A | No rewards/staking. |
| 19 | Missing state update before reward claim | N/A | No rewards. |
| 20 | Fee shares minted after distribution | N/A | No shares/fees. |
| 21 | `div(x,0)` returns 0 in assembly | N/A | Only assembly is `_bubbleRevert` (a `revert`), no division. |
| 22 | `type(uint256).max` as sentinel | N/A | No sentinel/max-uint usage. |
| 23 | Extreme weight ratios / exponentials | N/A | No exponentiation or weights. |
| 24 | Solidity time literals are `uint24` | N/A | No time literals (`1 days`, etc.). |
| 25 | Rounding direction must favor protocol | N/A | No rounding. |
| 26 | Off-by-one in comparison operators | N/A (verified) | Value check uses exact `!=`; balance checks use `<` for "insufficient", which is the correct boundary (equal balance is allowed). No `>`/`>=` ambiguity affecting funds. |
| 27 | Assigning negative value to uint reverts | N/A | No subtraction that could underflow (`totalValue` only accumulates via `+=`). |
| 28 | `unchecked` blocks need explicit validation | N/A | No `unchecked` blocks. |
| 29 | Precision loss compounds across operations | N/A | Single addition; nothing to compound. |
| 30 | Div-before-mul hidden by function calls | N/A | No math helper calls. |
| 31 | Rounding down to zero allows state changes | N/A | No rounding. |
| 32 | ~50% understatement from mixing precisions | N/A | Single precision (wei), no mixing. |
| 33 | Double-scaling across modules | N/A | No scaling. |
| 34 | Mismatched precision: decimals vs hardcoded 1e18 | N/A | No hardcoded precision constants. |
| 35 | Downcast overflow invalidates invariant checks | N/A | No downcasts. |
| 36 | Rounding direction leaks value (AMM `mulWadDown`) | N/A | No AMM/fee math. |

---

## Notes on non-precision numeric checks (informational, in-scope-adjacent)

These were examined because they involve comparisons on value-bearing paths;
all are correct and are recorded only for completeness:

- `withdrawEth`: `if (address(this).balance < amount) revert InsufficientBalance();`
  — strict `<` correctly permits withdrawing the full balance (`balance == amount`).
- `withdrawERC20`: `if (erc20.balanceOf(address(this)) < amount) revert ...;`
  — same correct boundary.
- `bundleExecute`: `if (totalValue != msg.value) revert IncorrectEthValue();`
  — exact match required; no leftover ETH can be stranded or over-spent.

No findings.
