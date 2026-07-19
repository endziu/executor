# Security Audit Report — `Executor` (multi-agent)

**Target:** `src/Executor.sol` (single contract, 244 lines) · `foundry.toml` · `script/Executor.s.sol`
**Commit:** `fd4e7ff` (`main`)
**Toolchain:** solc 0.8.36, `evm_version = osaka`, transient-storage reentrancy guard, immutable `OWNER`
**Date:** 2026-07-19
**Tests:** 54/54 passing at time of review.

> **Post-audit accounting change:** This report is an immutable record of commit
> `fd4e7ff`. A later implementation decoupled outgoing call values from fresh
> `msg.value`: `execute` now takes an explicit value, and bundle values may use
> the Executor's stored balance. The report's exact-`msg.value` statements are
> correct for the audited commit but do not describe the current implementation.

## Methodology

Seven specialist sub-agents (opus) ran in parallel, each walking a domain checklist from the `evm-audit` skill set and writing a `findings-<domain>.md` in this directory:

| Agent | Domain | Findings file |
|-------|--------|---------------|
| general | Core EVM footguns, external calls, reentrancy | `findings-general.md` |
| access-control | Ownership, privilege, centralization | `findings-access-control.md` |
| erc20 | Weird/non-standard token behavior | `findings-erc20.md` |
| dos | Gas griefing, unbounded loops, bricking | `findings-dos.md` |
| assembly | Inline Yul (`_bubbleRevert`), transient storage | `findings-assembly.md` |
| chain-specific | Multichain / L2 / hardfork portability | `findings-chain-specific.md` |
| precision-math | Overflow, rounding, comparisons | `findings-precision-math.md` |

This report synthesizes and **de-duplicates** their output, and **reconciles severity** where a specialist over-rated an operator-controlled configuration issue as a contract vulnerability (see §Severity reconciliation).

---

## Executive Summary

`Executor` is a deliberately powerful, single-owner arbitrary-call execution proxy. It is **well-constructed and free of externally-exploitable vulnerabilities.** The prior audit pass (L-1..L-4, `fd4e7ff`) closed the substantive contract-level issues, and the multi-agent sweep confirms the hardening holds: the reentrancy guard, codeless-target checks, weird-ERC20 handling, `msg.value` accounting, and the single assembly block are all provably correct.

**Every remaining finding is either (a) a deployment/configuration decision the operator controls, or (b) an owner-self-inflicted footgun that no third party can trigger.** There are **no Critical, High, or Medium contract vulnerabilities.**

The single most valuable takeaway is a **configuration fix**: `evm_version = osaka` needlessly restricts the deployable chain set to (effectively) post-Fusaka mainnet, while the contract's only real requirement is EIP-1153 transient storage (Cancun). Set `evm_version = "cancun"` and gate deployments on a verified chain list.

### Consolidated findings

| ID | Title | Severity | Source agents |
|----|-------|----------|---------------|
| F-1 | Deployment portability: `osaka` EVM target + transient guard restrict deployable chains; no `chainid` guard | Low | chain-specific (CS-1/CS-2), general (G-1) |
| F-2 | Deploy script does not verify the *intended* owner value or L1→L2 owner form | Low | access-control (AC-3), chain-specific (CS-5) |
| F-3 | zkSync Era not supported by this toolchain / `code.length` guard semantics differ | Low | chain-specific (CS-3) |
| F-4 | Strict `_safeTransfer` blocks a few non-standard tokens from `withdrawERC20` (recoverable via `execute`) | Low | erc20 (E-1) |
| F-5 | Total centralization by design — owner can execute anything and seize all held assets | Info | access-control (AC-1/AC-2) |
| F-6 | CREATE (nonce-based) deploy address is chain/reorg-dependent | Info | chain-specific (CS-4) |
| F-7 | Owner-self-inflicted gas / returndata / revert-based DoS vectors | Info | dos (D-1..D-4), general (G-2) |
| F-8 | Minor consistency & cosmetic items | Info | general (G-3), assembly (ASM-1), erc20 (E-2/E-3) |

---

## Severity reconciliation

The **chain-specific agent rated CS-1 and CS-2 as High** ("permanent DoS / funds locked"). This report **downgrades both to Low (folded into F-1)** for these reasons:

- The contract is **sound on its intended deployment target** (any Cancun+ chain). The failure mode requires an *operator* to deploy the artifact to an unsupported (pre-Cancun) chain — it is not reachable by any third party and is not a defect in the contract logic.
- "Permanent DoS" here is a deployment mistake, fully prevented by a one-line config change plus a deploy-time chain check, both recommended below.
- Standard audit convention rates operator-controlled misconfiguration that the code itself can't be blamed for as Low/Info, reserving High for attacker-reachable conditional fund loss.

CS-3 (zkSync) is likewise downgraded from Medium to Low (F-3): it is a "won't compile / out of scope" portability gap, not an exploitable bug. The *recommendations* from all three stand regardless of label — they are the most actionable output of this audit.

---

## Detailed Findings

### [F-1] Deployment portability — `osaka` EVM target and transient guard restrict the deployable chain set
**Severity:** Low · **Location:** `foundry.toml:6` (`evm_version = "osaka"`), `src/Executor.sol:19` (`bool private transient locked`)

The reentrancy guard compiles to `TSTORE`/`TLOAD` (EIP-1153, Cancun+). On any pre-Cancun chain these are invalid opcodes; because `_nonReentrantBefore` runs first in every mutating function, all four value-moving functions would revert on entry while `receive()` still accepts ETH — a fund-and-never-empty contract with no recovery (immutable owner). Separately, `evm_version = osaka` (Fusaka, ~mainnet-only in mid-2026) is a *superset* of Cancun: it does not help the transient requirement and strictly *narrows* the safe chain set, since every current L2 (Arbitrum, OP/Base, Polygon, BNB, Scroll, Gnosis) trails Fusaka. The contract uses no Osaka-only feature. The README's "track latest solc/Foundry" routine also silently ratchets `evm_version` forward, potentially emitting newer opcodes with no source change.

**Failure mode.** Deploy the `osaka` artifact to a Cancun-but-not-Fusaka L2 → any Osaka-only opcode solc emits reverts / misprices. Deploy to a pre-Cancun chain → `TSTORE` bricks all withdrawals; ETH sent via `receive()` is stranded.

**Recommendation.**
1. Set `evm_version = "cancun"` — the minimum that satisfies the transient guard.
2. Decouple `evm_version` from the toolchain-freshness routine; pin it to the oldest EVM all deploy targets support.
3. Add `require(block.chainid == <expected>, "wrong chain")` to `script/Executor.s.sol` and gate deploys on a verified EIP-1153 chain allow-list.

### [F-2] Deploy script does not verify the *intended* owner
**Severity:** Low · **Location:** `script/Executor.s.sol:11-17`, plus L1→L2 aliasing (`src/Executor.sol:67-78`)

`OWNER` is immutable and taken from `vm.envAddress("OWNER")`. The post-deploy `require(executor.OWNER() == owner)` compares the supplied value to itself, so a *wrong-but-valid* address (typo, or the raw L1 address where the **aliased** `L1addr + 0x1111…1111` is required for L1-contract control on Arbitrum/OP-Stack) is silently accepted and is **unrecoverable** — every `onlyOwner` call reverts `NotOwner` forever and any held assets are frozen.

**Recommendation.** In the deploy script/runbook: (a) assert the owner is a contract/multisig where intended (`owner.code.length > 0`); (b) document per-chain which address form to use (aliased vs raw); (c) verify the resolved owner on a block explorer post-deploy before funding.

### [F-3] zkSync Era incompatibility
**Severity:** Low · **Location:** build config; `src/Executor.sol:99, 139, 179`

zkSync Era is not EVM-bytecode-equivalent: it requires `zksolc` (this build produces no zkSync artifact), its `EXTCODESIZE` returns 0 for some system contracts / during construction (so the three `code.length == 0` guards can false-positive and reject legitimate targets/tokens), and its CREATE/CREATE2 address derivation differs. **Recommendation.** Exclude zkSync (and non-EVM-equivalent zk chains), or maintain a separate `zksolc` build and re-audit the `code.length` guards under zkSync semantics.

### [F-4] Strict `_safeTransfer` blocks a few non-standard tokens from `withdrawERC20`
**Severity:** Low · **Location:** `withdrawERC20` (`:175-186`), `_safeTransfer` (`:210-228`)

`_safeTransfer` correctly treats a `false`/short/dirty return or a call-revert as `ERC20TransferFailed`. As a side effect, the dedicated withdrawal path reverts for some legitimate-but-weird tokens: return-`false`-on-success (Tether Gold class), zero-amount-revert tokens when `amount == 0` (LEND/BNB), and `uint96`-capped tokens (UNI/COMP) above 2^96−1 held units. **No funds are ever locked** — the owner recovers via `execute(token, transfer(to, amount))`, which only checks call-level success. **Recommendation.** Keep strict `_safeTransfer`; document the `execute` escape hatch in `withdrawERC20` NatSpec; optionally reject `amount == 0` for a clear error.

### [F-5] Total centralization by design
**Severity:** Info · **Location:** whole contract

The owner can call any contract with any calldata/value and withdraw all ETH/ERC20. `OWNER` is immutable — no transfer/renounce/timelock/pause/multisig, so a compromised key means instant total loss and a lost key means permanent lockout (redeploy + migrate only). Any assets a third party sends (via `receive()` or a token transfer) become fully owner-controlled. This is the intended, documented trust model for a personal execution proxy — no third-party funds are induced or at precondition-free risk. **Recommendation.** Deploy with a multisig / smart-account (Safe) as `OWNER`; keep the README warning prominent; sweep balances rather than parking them.

### [F-6] CREATE (nonce-based) deploy address is chain/reorg-dependent
**Severity:** Info · **Location:** `script/Executor.s.sol:14`

Plain CREATE means the address depends on deployer + nonce; there is no deterministic cross-chain address, and on reorg-prone chains a nonce reordering can land the contract at a different address, stranding any ETH pre-sent to the predicted address. **Recommendation.** Don't pre-fund before finality; use a CREATE2 factory with a fixed salt if deterministic cross-chain addresses are needed; otherwise record the actual per-chain address after finality.

### [F-7] Owner-self-inflicted gas / returndata / revert DoS
**Severity:** Info · **Location:** `bundleExecute` loops (`:132-143`), `execute` returndata (`:102`), `_bubbleRevert` (`:235-241`), `withdrawERC20` `balanceOf` (`:182`), `withdrawEth` recipient (`:159-163`)

Unbounded owner-supplied bundle arrays, returndata copied from owner-chosen targets in `execute`/bubble paths, a reverting-`balanceOf` token blocking `withdrawERC20`, and a reverting ETH recipient blocking `withdrawEth` are all reachable **only inside an owner-initiated tx with owner-chosen inputs**, each with a recovery path (retry / `execute` escape hatch). No third party can trigger any of them. Notable good design: `bundleExecute` discards its return value (`(bool success,)`), making the batch path immune to returndata bombing. **Recommendation.** None required; optional `try/catch` on the `balanceOf` read and a documented bundle-size cap are hardening only.

### [F-8] Minor consistency & cosmetic items
**Severity:** Info

- **`execute`/`bundleExecute` allow `target == address(this)`** while the withdraw functions reject `to == address(this)` — not exploitable (self-calls into mutating functions revert on the reentrancy guard *and* `onlyOwner`), just an asymmetry that can emit self-referential events. (general G-3)
- **`execute` swallows the target's revert reason** (`ExecutionFailed(0)`) while withdrawals bubble it — a diagnosability gap, not a security issue.
- **Zero-amount `withdrawEth`/`withdrawERC20`** emit phantom `*Withdrawn(0, …)` events.
- **`_bubbleRevert` lacks the `"memory-safe"` annotation** — the Yul is provably correct (`revert(add(32, returndata), mload(returndata))` re-reverts the exact buffer, OZ pattern); adding `assembly ("memory-safe")` is the current idiom. (assembly ASM-1)
- **Blocklist/pause tokens** (USDC/USDT) can freeze held balances at the token level — inherent counterparty risk, no in-contract mitigation. (erc20 E-2)
- **ERC777/677 reentrant tokens** via arbitrary `execute` are fully contained by the transient guard. (erc20 E-3)

---

## Positive Controls (verified sound across agents)

- **Reentrancy guard is correct and cannot be bricked** — `bool private transient locked` (EIP-1153); set-before / clear-after, and transient storage is discarded at end-of-tx, so a bubbled revert can never wedge it. Placed first in the modifier list; self-reentry is double-blocked (guard + `onlyOwner` on the internal caller).
- **`_bubbleRevert` assembly is provably correct** — right offset/length math, reads-then-reverts, no FMP corruption, touches no state.
- **Codeless-target rejection** on any calldata-bearing leg (`TargetNotContract`) and on `withdrawERC20` tokens; bare ETH sends to EOAs intentionally allowed.
- **Weird-ERC20 handling** in `_safeTransfer` matches OZ SafeERC20 (no-return, short/dirty-return, revert-bubble); no internal accounting means fee-on-transfer/rebasing/decimals/flash-mint/max-amount classes don't apply.
- **`bundleExecute` value accounting** — checked sum, `sum(values) == msg.value`, per-leg `values[i]` forwarding: no `msg.value` reuse / double-spend.
- **Access control** — every mutating function `onlyOwner nonReentrant`; constructor rejects the zero owner; no upgrade/`delegatecall`/init surface.
- **Arithmetic** — trivial and fully checked under 0.8.36; no rounding/precision/downcast/off-by-one surface.
- **No signature / permit / oracle / proxy / NFT surface** — those vulnerability classes are entirely N/A.

---

## Issue Filing

The audit found **nothing at Medium severity or above**, so per the audit methodology **no GitHub issues are filed**. If you'd like, I can open tracking issues for the two most actionable Lows — **F-1** (`evm_version = "cancun"` + deploy `chainid`/EIP-1153 gating) and **F-2** (deploy-script owner verification) — labeled `low` / `ready-for-human`. Say the word and I'll file them.

## Recommended actions (prioritized)

1. **F-1** — `evm_version = "cancun"`; add a `block.chainid` check and EIP-1153 chain allow-list to the deploy flow. *(config + deploy script; highest value)*
2. **F-2** — verify the intended owner (contract/multisig, correct L1→L2 form) in the deploy runbook. *(irreversible if wrong)*
3. **F-5** — use a Safe/multisig as `OWNER`. *(operational)*
4. **F-3 / F-4 / F-8** — document zkSync exclusion, the `execute` escape hatch for weird tokens, and apply the cosmetic cleanups if desired. *(docs + optional polish)*
