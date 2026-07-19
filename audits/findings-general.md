# Executor — General EVM Checklist Audit

> **Post-audit accounting change:** This historical review describes commit
> `fd4e7ff`. Subsequent work gave `execute` an explicit outgoing value and lets
> bundles draw from the Executor's available balance. Exact-`msg.value`
> statements below remain accurate for the audited commit, not current code.

**Scope**: `src/Executor.sol` (owner-controlled arbitrary-call execution proxy)
**Toolchain**: solc 0.8.36, `evm_version = osaka`, transient-storage reentrancy guard, immutable `OWNER`
**Threat model**: `OWNER` is fully trusted. Findings focus on what a *third party* (non-owner) can do, and separate genuine issues from owner-self-inflicted footguns.
**Prior work**: lows L-1..L-4 fixed in `fd4e7ff` (short/dirty ERC20 return, codeless-target guard, `to==address(this)` on withdraws, `Executed` result hashing). Not re-reported below.

---

## [G-1] Contract compiled for a future `osaka` EVM target — bytecode is non-portable
**Severity**: Low
**Category**: general
**Location**: `foundry.toml` (`evm_version = "osaka"`, `solc = "0.8.36"`), `src/Executor.sol:2`
**Description**: The checklist flags opcode/hardfork portability (PUSH0 >=0.8.20, `[multichain-auditor MC-03]`). The project pins `evm_version = osaka` — a hardfork newer than Prague/Pectra. Bytecode compiled for `osaka` may emit opcodes (or opcode gas semantics) that are not yet live on many mainnet-equivalent chains and most L2s. Deploying the same artifact to a chain whose EVM is behind `osaka` can produce reverting/invalid-opcode behavior at deploy or run time. The transient-storage guard (`bool transient locked`) additionally requires TSTORE/TLOAD (Cancun+), so any target chain below Cancun cannot run this contract at all.
**Proof of Concept**: Deploy the compiled artifact to an EVM chain that has not activated `osaka` (or is pre-Cancun). Constructor/runtime opcodes are rejected or misprice. No attacker needed — this is a deployment-portability latent issue.
**Recommendation**: Deliberately choose the lowest `evm_version` that supports transient storage (`cancun`) unless an `osaka`-only feature is actually required. Document the minimum supported hardfork per target chain in README, and confirm each deployment chain has activated it before shipping the artifact.

## [G-2] `execute()` copies untrusted returndata into memory and returns it — memory-expansion griefing
**Severity**: Info
**Category**: general
**Location**: `execute()` `src/Executor.sol:102`, `_bubbleRevert()` `src/Executor.sol:235-241`, `_safeTransfer()` `src/Executor.sol:212`
**Description**: Checklist items E-04 / RareSkills "returning large memory arrays for gas griefing": a low-level `.call` to an untrusted address lets the callee return an arbitrarily large `bytes` buffer, which Solidity copies into memory (quadratic gas). `fd4e7ff` already removed the *amplified* path (the `Executed` event now stores `keccak256(result)` instead of the raw buffer), but `execute()` still assigns the full returndata to `result` and returns it, and `_bubbleRevert` / `_safeTransfer` copy revert returndata. Because every mutating function is `onlyOwner`, the target/token addresses are owner-chosen, so a returndata bomb only griefs the owner's own transaction — no third party can trigger it and no funds are at risk. Noted for completeness only.
**Proof of Concept**: Owner calls `execute(evilTarget, data)` where `evilTarget` returns megabytes of data; the owner's own tx pays quadratic memory gas / OOGs. Not reachable by a non-owner.
**Recommendation**: Optional hardening — bound the returndata copied back to the caller with inline assembly (`returndatacopy` up to a cap) if a bounded return value is acceptable. Low priority given the trusted-owner model.

## [G-3] `execute()` / `bundleExecute()` do not reject `target == address(this)` (asymmetric with withdraw guards)
**Severity**: Info
**Category**: general
**Location**: `execute()` `src/Executor.sol:94`, `bundleExecute()` `src/Executor.sol:137-143`
**Description**: Checklist "receiver pointing to another system contract" / "if (receiver == caller) unexpected behavior" [G-31, G-08]. `withdrawEth`/`withdrawERC20` explicitly reject `to == address(this)` (L-3), but `execute`/`bundleExecute` allow `target == address(this)`. This is not exploitable: any self-call that re-enters a mutating function hits the transient guard (`locked == true`) and reverts with `ReentrancyGuard`, cascading to `ExecutionFailed`; a self-call to a `view` function or a bare ETH self-forward (empty data) is a net-zero no-op that merely leaves ETH in the contract and emits an `Executed`/`BundleExecuted` event with `address(this)` as target. No trust boundary is crossed and only the owner can invoke it. Flagged only as a consistency gap with the withdraw functions.
**Proof of Concept**: `execute{value: 1 ether}(address(executor), "")` succeeds, ETH stays in the contract, `Executed(address(this), ...)` is emitted. `execute(address(executor), <withdrawEth selector>)` reverts (`ReentrancyGuard` -> `ExecutionFailed(0)`).
**Recommendation**: Optional — reject `target == address(this)` in both functions for symmetry and to avoid self-referential events. No security impact.

---

## Checklist coverage — items verified SOUND

**External calls & low-level interactions**
- *Call to non-existent address returns true* (E-05): guarded — `execute`/`bundleExecute` revert `TargetNotContract` when `data.length > 0 && code.length == 0`; `withdrawERC20` checks `token.code.length`. Bare ETH sends to EOAs are intentionally allowed. Sound.
- *Fixed gas in `.call{gas:X}`* (E-03): no hardcoded gas; forwards all available gas. Sound.
- *ETH transfer via `transfer()`/`send()`* (E-07): uses `.call{value:}("")` everywhere. Sound.
- *Unchecked return of low-level call* (SWC-104): every `.call` checks `success` and reverts (`ExecutionFailed` / `EthTransferFailed` / `ERC20TransferFailed`). Sound.
- *Returndata bombing* (E-04): amplified event path already fixed; residual is owner-only — see G-2.
- *`abi.encodePacked` collisions* (G-15): only `abi.encodeWithSignature("transfer(address,uint256)",...)` and single-arg `keccak256` used. Sound.
- *delegatecall to stateful contracts* (E-09/E-10): no `delegatecall` anywhere. Sound.
- *try/catch OOG* (G-18): no try/catch. N/A.

**`msg.value` in loops / multicall** (E-17, L-03, Opyn): `bundleExecute` sums `values[]` and enforces `totalValue == msg.value`; each leg forwards its own `values[i]`. No double-spend. Sound.

**Force-feeding (G-03)**: no invariant depends on `address(this).balance`; `getBalance` and the `balance < amount` withdraw checks tolerate force-fed ETH (owner can withdraw it). Sound.

**Direct token transfers bypass accounting (V-01/G-07)**: no internal ERC20 accounting; `withdrawERC20` reads live `balanceOf`. Fee-on-transfer / rebasing tokens are handled correctly for a pull-withdraw (no stored-balance drift). Sound.

**Reentrancy (non-obvious)**
- *nonReentrant must be first* (G-17): modifier order is `nonReentrant onlyOwner` — guard set before the (view-only) owner check. Sound.
- *Cross-contract / read-only reentrancy* (G-20/G-21): single self-contained contract, no shared/proxy storage, no share-price or accounting view consumed by other contracts during a callback. N/A.
- *ERC721/ERC777 hooks* (NFT-02/FT-08): guard covers all mutating entrypoints; callbacks that re-enter revert. Sound.
- Transient-storage guard (`bool transient locked`) correctly reverts on nested entry and auto-clears at tx end.

**Access control**: `OWNER` immutable, set non-zero in constructor (`ZeroAddress` check); all mutating functions `onlyOwner`. Sound.

**Array/loop hazards**: `bundleExecute` loops over owner-supplied arrays only; array-length mismatch reverts (`MismatchedArrays`), empty reverts (`NoTargets`). Any gas-limit DoS is owner-self-inflicted, not attacker-reachable. No duplicate-address double-payment accounting exists. Sound.

**Block/time assumptions (G-28/MC-01)**: no `block.timestamp` / `block.number` usage. N/A.

**Comparison & logic operators (G-29/G-30)**: balance checks use `<` with matching `InsufficientBalance`/`InsufficientTokenBalance`; `totalValue != msg.value` exact-match. No off-by-one. Sound.

**Merkle / pause / ERC4626 inflation / auctions / refinancing / semantic overloading / storage-pointer / downcast / unchecked blocks**: none of these constructs exist in the contract. N/A.

**Deployment script (G-13)**: `script/Executor.s.sol` reads `OWNER` from env, deploys, and asserts `executor.OWNER() == owner` post-deploy. Sound.

**Documentation-code match (F-07/G-12)**: NatSpec and inline comments (codeless-target rationale, result-hash rationale, SafeERC20 parity) match the implementation. Sound.
