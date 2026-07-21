# Findings — Assembly / Yul

**Target:** `src/Executor.sol` · **Verdict:** the single assembly block (`_bubbleRevert`, lines 235-241) is correct. No Critical/High/Medium/Low — one Info best-practice item.

## Correctness of `_bubbleRevert`

```solidity
assembly { revert(add(32, returndata), mload(returndata)) }   // gated by returndata.length > 0
```

For a `bytes memory` value, `returndata` holds the address of the length word. So `mload(returndata)` = byte length, `add(32, returndata)` = address of the first data byte, and `revert(dataStart, length)` re-emits the buffer byte-for-byte. This is exactly the OpenZeppelin bubbling pattern — the offset/length math is right.

## [ASM-1] Assembly block not annotated `"memory-safe"`
**Severity:** Info · **Category:** assembly · **Location:** `src/Executor.sol:237-239`

**Description.** The block is genuinely memory-safe (reads only, then reverts) but is not annotated `assembly ("memory-safe")`. Absence is conservative/safe under via-IR, but the annotation is the current-Solidity idiom and carries zero risk here since the block unconditionally reverts.

**Recommendation.** `assembly ("memory-safe") { revert(add(32, returndata), mload(returndata)) }`

## Checklist coverage (walked, verified sound)
- **Revert pointer/offset math** — CORRECT (see above).
- **Free-memory-pointer corruption** — N/A. No `mstore`/allocation, never touches `0x40`; `revert` terminates the context.
- **Dirty upper bits** — N/A. Only a clean length word is loaded; no sub-word/`address` loads needing masking.
- **Memory-expansion gas bomb** — N/A. `length` comes from a buffer Solidity already materialized during the `.call`. (The returndata-bomb vector in the `Executed` event was separately closed by L-4 hashing `result`.)
- **div/shift/signextend/overflow/create2/returndatacopy quirks** — N/A, none present.
- **`private pure`** — CORRECT; reads memory and reverts, touches no state.
- **Call-to-codeless-address** — HANDLED: `execute`/`bundleExecute` require `target.code.length > 0` for any leg with calldata; `withdrawERC20` requires `token.code.length > 0`. Bare ETH sends to EOAs intentionally allowed.
- **Transient reentrancy guard** (`bool private transient locked`, EIP-1153) — CORRECT: reverts-if-set then sets in `_nonReentrantBefore`, clears in `_nonReentrantAfter`; transient storage rolls back on revert and auto-clears per-tx, so a bubbled revert can't wedge the guard.
