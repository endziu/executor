# Findings — DoS & Gas Griefing

**Threat model.** Every state-changing entry point (`execute`, `bundleExecute`, `withdrawEth`, `withdrawERC20`) is `onlyOwner`. The only unauthenticated surface is `receive()` (accepts ETH, does nothing else) and two view getters. **No non-owner can drive the contract into DoS or a brick state.** Every gas/revert vector is reachable only inside an owner-initiated tx with owner-chosen targets/tokens/recipients → owner-self-inflicted → Info.

**Result:** Critical 0, High 0, Medium 0, Low 0, Info 4.

## [D-1] Unbounded loops in `bundleExecute` are owner-gas-bounded only
**Severity:** Info · **Location:** `src/Executor.sol:132-134` (value-sum loop), `:137-143` (call loop)

Both loops iterate over owner-supplied `targets`/`data`/`values` with no length cap, but these are calldata params of an `onlyOwner` call, not attacker-growable persistent state. A too-large bundle only reverts the owner's own atomic tx. No shared queue or third-party funds affected. **Recommendation:** none required; optionally document a per-bundle cap, or add a hard `targets.length` cap only if bundles are ever driven by semi-trusted automation.

## [D-2] Returndata from owner-chosen targets copied to memory in `execute` and bubble paths
**Severity:** Info · **Location:** `execute` `:102`; `_bubbleRevert` `:235-241` via `withdrawEth` `:159-162` and `_safeTransfer` `:212-217`

L-4 already removed the event-side amplifier (emits `keccak256(result)`). Residual copies: `execute` assigns full returndata into `result` (returned to caller); `withdrawEth`/`_safeTransfer` assign and re-`revert` raw returndata. All addresses are owner-supplied, so any memory-expansion gas is owner-chosen and owner-paid. **Good design:** `bundleExecute` discards its return value (`(bool success,)` at `:141`), so it performs **no** returndata copy and is immune to bombing across all legs. **Recommendation:** accept as-is; if a hard guarantee is wanted, have `execute` return a hash/length or cap bubbled length.

## [D-3] `withdrawERC20` reads `balanceOf` with no try/catch — reverting token blocks that path (escape hatch exists)
**Severity:** Info · **Location:** `src/Executor.sol:182`

`erc20.balanceOf(address(this))` is unguarded; a paused/malicious token whose `balanceOf` reverts makes `withdrawERC20` revert for that token. **Not a permanent lock:** the owner can sweep via `execute(token, transfer(to, amount))`, which never touches `balanceOf`. **Recommendation:** optional `try/catch` on the read, or drop the pre-check and let the transfer gate on failure. Not required given the `execute` escape hatch.

## [D-4] `withdrawEth` reverts if the owner-chosen recipient rejects ETH (not a lock)
**Severity:** Info · **Location:** `src/Executor.sol:159-163`

If `to` reverts on receipt, `withdrawEth` reverts. `to` is an owner-chosen parameter (no stored beneficiary), so the owner retries with an accepting address; funds are never stranded. **Recommendation:** none — reverting correctly surfaces the recipient's failure rather than silently losing funds.

## Checklist coverage — verified sound
- **Reentrancy-guard permanent brick (key concern): SOUND.** `locked` is `bool private transient` (EIP-1153). Even though `_nonReentrantAfter` runs *after* the external call, a revert in the guarded body unwinds the tx and transient storage is discarded at end-of-transaction regardless, so `locked` can never persist `true` into a later tx. The guard cannot be permanently bricked.
- **Returndata bombing in `bundleExecute`**: return discarded (`:141`) → no copy → immune.
- **Gas forwarding (SWC-126)**: no fixed `.call{gas:X}()`; all calls forward remaining gas. Sound.
- **try/catch griefing**: low-level `call` + explicit `success` checks, no forceable catch branch. Sound.
- **Unbounded loops / L2 array-filling**: only `onlyOwner` calldata-array loops, no attacker-growable state.
- **Blocklisted recipient**: single owner-chosen recipient per withdrawal; no batched multi-recipient distribution to brick. Sound.
- **Zero-amount revert / block stuffing / timelock / economic / paymaster / oracle**: N/A — none in scope.
- **Pause DoS / pause brick**: no pause mechanism; ownership immutable by design. N/A.
- **Overflow-revert DoS**: `totalValue += values[i]` is checked arithmetic; overflow reverts owner's own tx. Sound.

## Summary
No third-party DoS or permanent-brick vector exists; all state-changers are `onlyOwner`. Every vector (unbounded bundle loop, execute/bubble returndata copy, `balanceOf` revert, ETH-recipient revert) is owner-self-inflicted with a recovery path → Info. The reentrancy guard is sound (transient storage discarded end-of-tx). `bundleExecute` discarding returndata makes the batch path immune to bombing. No code change required for security.
