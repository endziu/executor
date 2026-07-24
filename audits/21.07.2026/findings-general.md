# Executor — General EVM Checklist Audit (second pass)

**Scope**: `src/Executor.sol`, `script/Executor.s.sol`, `foundry.toml`
**Toolchain**: solc 0.8.36, `evm_version = "cancun"`, transient-storage reentrancy guard, immutable `OWNER`
**Deployment target**: Base mainnet (`8453`) / Base Sepolia (`84532`) only, enforced by a default-deny chain allow-list in the deploy script.
**Threat model**: `OWNER` is fully trusted. Every mutating entrypoint is `onlyOwner`; the only non-owner surface is `receive()` (accepts ETH). Owner-only-reachable issues cap at Medium; no third-party funds are induced or put at precondition-free risk.
**Focus of this pass**: the **new explicit-value ETH accounting model** (`execute(target, data, value)` sends an explicit `value`; `bundleExecute` checks `sum(values)` against `address(this).balance` at entry; stored ETH and fresh `msg.value` are fungible; excess `msg.value` stays deposited). This model was NOT covered by the first audit.
**Prior findings not re-reported**: F-5 (centralization, accepted), F-7 (owner-self-DoS, accepted), F-8 accepted items (self-target asymmetry, blocklist/pause tokens, reentrant tokens), F-3 (zkSync, excluded by policy). None are changed in impact by the new code.
**Status**: `forge build` clean, **74/74** tests passing.

---

The new explicit-value model was scrutinized specifically for double-spend of `msg.value`, balance-check bypass, cross-leg value accounting with ETH refunded to the Executor mid-bundle, and interaction with `nonReentrant`. **No Critical/High/Medium/Low security issue was found in the new model or elsewhere.** The two items below are Info-level consistency/documentation notes with no security impact. The explicit-value design is analysed in detail under "Verified sound".

## [G-1] `bundleExecute` accepts empty no-op legs that `execute` rejects
**Severity**: Info
**Category**: general
**Location**: `execute()` `src/Executor.sol:98`, `bundleExecute()` `src/Executor.sol:147-153`
**Description**: `execute` rejects a fully empty call with `if (value == 0 && data.length == 0) revert NoTransactionData()`. `bundleExecute` has no equivalent per-leg guard, so a bundle leg with `values[i] == 0` and `data[i].length == 0` is a permitted no-op: `targets[i].call{value: 0}("")` returns `(true, "")` for any non-zero, non-`address(0)` target (contract or EOA). This is a benign asymmetry — the leg does nothing, moves no value, and only contributes to the emitted `BundleExecuted` event. Not exploitable and reachable only by the owner. `testBundleExecuteWithZeroValues` explicitly exercises and accepts this behavior.
**Proof of Concept**: `bundleExecute([alice], [""], [0])` succeeds and emits `BundleExecuted` with a no-op leg; the same shape via `execute(alice, "", 0)` reverts `NoTransactionData`.
**Recommendation**: None required. If strict parity is wanted, add `if (values[i] == 0 && data[i].length == 0) revert NoTransactionData();` inside the loop. Purely cosmetic.

## [G-2] Bundle sum-check rejects bundles fundable only via intra-bundle ETH refunds
**Severity**: Info
**Category**: general
**Location**: `bundleExecute()` `src/Executor.sol:141-145`
**Description**: The bundle guard checks `sum(values) > address(this).balance` **once, at entry**. If an early leg sends ETH to a target that forwards ETH back into the Executor via `receive()` (raising the live balance), a later leg still cannot draw on that refill, because the upfront sum ceiling is the balance at entry, not the running balance. This is a deliberately conservative choice, not a bug: it is the safe direction (reject-rather-than-overspend), and it is precisely what prevents any cross-leg double-spend (see Verified sound). It only surfaces as a usability limit for exotic "route ETH through a contract and re-spend the return within one bundle" flows, which the owner can always split across two transactions.
**Proof of Concept**: Balance = 1 ETH. `bundleExecute([refunder, sink], [d0, d1], [1 ether, 1 ether])` where `refunder` returns its 1 ETH to the Executor. `totalValue = 2 ETH > 1 ETH` reverts `InsufficientBalance`, even though sequential execution would be fundable after the refund.
**Recommendation**: None — keep the upfront sum ceiling; it is the property that makes the model safe. Document the "one bundle cannot re-spend its own intra-bundle ETH returns" behavior if operators are likely to attempt it.

---

## Verified sound

### New explicit-value ETH accounting model — analysed, sound
- **No `msg.value` double-spend / reuse.** There is no `delegatecall` and no multicall-over-`msg.value` pattern. `msg.value` is never read; it simply lands in `address(this).balance` (the function is `payable`). Outgoing amounts are the explicit `value` / `values[i]`. The classic "same `msg.value` counted per iteration" footgun (checklist E-17 / "msg.value reused in loops") does not apply — each leg forwards its own fixed `values[i]` from real balance. `testFuzzBundleExecuteForwardsExactValues` confirms per-leg forwarding.
- **Balance check cannot be bypassed.** `execute`: `value > address(this).balance` reverts `InsufficientBalance` (balance already includes the incoming `msg.value`, giving the documented stored/fresh fungibility). `bundleExecute`: `sum(values) > address(this).balance` reverts. The sum is computed in **checked** arithmetic (`totalValue += values[i]`), so a value array engineered to overflow the sum reverts rather than wrapping to a small total — verified by `testCannotBundleExecuteWhenValueSumOverflows`.
- **Cross-leg accounting is safe even when a leg refunds the Executor.** Because `sum(values) <= balanceAtEntry` is enforced upfront and each leg reduces the balance by at most its fixed `values[i]`, the cumulative outflow across the loop can never exceed `balanceAtEntry`; every individual `targets[i].call{value: values[i]}` is therefore always fundable and cannot underflow the EVM balance. A leg refunding ETH via `receive()` only raises the live balance — it can never be leveraged to spend more than `balanceAtEntry` (see G-2). No double-spend, no overspend.
- **`nonReentrant` interaction.** `receive()` is intentionally unguarded (must accept ETH, including refunds from a bundle leg) and is a pure balance increment with no state transition — safe to re-enter. Every value-moving function (`execute`, `bundleExecute`, `withdrawEth`, `withdrawERC20`) is `nonReentrant` with the guard listed first, so a bundle/execute target that tries to re-enter any of them reverts `ReentrancyGuard`, rolling back the whole outer call. `testBundleExecuteFailureRollsBackStoredAndFreshEther` confirms atomic rollback of both stored and fresh ether on a failed leg. The transient (`bool transient locked`) guard auto-clears at end-of-tx, so a bubbled revert cannot wedge it.
- **Excess funding handling.** Any `msg.value` beyond what the call/bundle spends stays in the contract (`testExecute...RetainsExcess*`, `testBundleExecuteRetainsExcessFreshEther`) and is withdrawable by the owner — no stranded-ETH or lost-refund path.

### Prior fixes verified to hold
- **F-1 (portability):** `foundry.toml` now pins `evm_version = "cancun"`; `script/Executor.s.sol` reverts `UnsupportedChain` on any chain other than `8453`/`84532` (default-deny). No Osaka-only opcodes; transient guard requirement (Cancun) satisfied.
- **F-8 fixed items:** `execute` now bubbles the target's revert reason via `_bubbleRevert` with an empty-data fall-through to `ExecutionFailed(0)` (`:107-113`); `withdrawEth`/`withdrawERC20` reject `amount == 0` with `ZeroAmount` (`:167`, `:200`), killing phantom zero events; `_bubbleRevert` carries the `assembly ("memory-safe")` annotation (`:258`) and the offset/length math (`revert(add(32, returndata), mload(returndata))`) is correct.

### Checklist areas confirmed clean (unchanged from first pass)
- **External calls:** codeless-target rejection on any calldata-bearing leg (`TargetNotContract`) and on `withdrawERC20` tokens; bare ETH sends to EOAs intentionally allowed; every `.call` checks `success`; no hardcoded gas; ETH moved only via `.call{value:}("")`; no `abi.encodePacked` collision surface; no `delegatecall`; no `try/catch`.
- **Returndata bombing:** `Executed` stores `keccak256(result)` (not the raw buffer); `bundleExecute` discards return data (`(bool success,)`); residual owner-only return copy in `execute` is F-7 (accepted).
- **Force-feeding:** no invariant depends on `address(this).balance`; force-fed ETH is simply withdrawable by the owner.
- **Weird ERC20:** `_safeTransfer` matches OZ SafeERC20 (no-return / short / dirty return / revert-bubble); no internal accounting, so fee-on-transfer / rebasing / decimals classes are N/A; documented `execute` escape hatch for the few non-standard tokens (F-4).
- **Reentrancy:** guard first in modifier order; single self-contained contract, no shared/proxy/read-only-reentrancy surface; ERC721/777 callbacks that re-enter revert.
- **Access control:** `OWNER` immutable, non-zero-checked in constructor; all mutating functions `onlyOwner`; no upgrade/init/`delegatecall` surface.
- **Arithmetic / comparisons:** trivial and fully checked under 0.8.36; balance checks use `<`/`>` with matching errors; no off-by-one, downcast, unchecked block, or storage-pointer surface.
- **Block/time, Merkle, pause, ERC4626, auctions, signatures, oracles:** none of these constructs exist. N/A.
- **Deployment script:** reads `OWNER` from env, deploys, asserts `executor.OWNER() == owner`, logs address + resolved owner for out-of-band verification; chain-gated default-deny. Sound.

---

**Summary — Critical: 0 · High: 0 · Medium: 0 · Low: 0 · Info: 2**
