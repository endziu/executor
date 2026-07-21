# Second Security Audit Report — `Executor` (multi-agent, pre-Base-mainnet)

**Target:** `src/Executor.sol` (265 lines) · `script/Executor.s.sol` · `foundry.toml`
**Commit:** `4aaed4f` (`main`)
**Toolchain:** solc 0.8.36, `evm_version = "cancun"`, transient-storage reentrancy guard, immutable `OWNER`
**Deployment scope:** Base mainnet (`8453`) / Base Sepolia (`84532`) only, enforced by the deploy-script allow-list
**Date:** 2026-07-21
**Tests:** 74/74 passing at time of review (`forge build` clean, verified directly).
**Prior audit:** [`../20.07.2026/AUDIT-REPORT.md`](../20.07.2026/AUDIT-REPORT.md) at commit `fd4e7ff`, remediated per [`../20.07.2026/REMEDIATION.md`](../20.07.2026/REMEDIATION.md).

## Why a second pass

The first audit's record is explicit that it describes the old exact-`msg.value`
accounting. After it closed, the ETH model changed (issues #3/#4, commit `949746c`):
`execute(target, data, value)` now takes an **explicit value**, `bundleExecute`
checks `sum(values[i])` against `address(this).balance` **at entry**, stored ETH and
fresh `msg.value` are fungible, and excess funding stays deposited. That model was
the primary unaudited surface for this pass, alongside re-verification of the
F-1..F-8 remediations.

## Methodology

Seven specialist sub-agents ran in parallel, each walking its `evm-audit` domain
checklist against the current code with the prior report and remediation record as
context:

| Agent | Domain | Findings file | Result |
|-------|--------|---------------|--------|
| general | Core EVM footguns, external calls, reentrancy | `findings-general.md` | 2 Info |
| precision-math | Overflow, comparisons, sum arithmetic | `findings-precision-math.md` | 2 Info |
| erc20 | Weird/non-standard token behavior | `findings-erc20.md` | 1 Info |
| assembly | Inline Yul, memory-safety, transient storage | `findings-assembly.md` | 1 Info |
| chain-specific | Base/OP-Stack semantics, hardfork/opcodes, aliasing | `findings-chain-specific.md` | 1 Low |
| access-control | Ownership, privilege, new payable surface | `findings-access-control.md` | 1 Low, 1 Info |
| dos | Gas griefing, deposit griefing, wedging | `findings-dos.md` | 2 Info |

In parallel, a two-axis code review (Standards / Spec) ran over
`git diff fd4e7ff...HEAD` — the full delta since the previously audited commit —
checking repo-convention conformance and faithfulness to issues #3/#4 and the
remediation epic #5 (#6–#13). Its results are folded into SF-1 below.

---

## Executive Summary

**No Critical, High, or Medium findings. The contract is sound and ready for Base
mainnet deployment.** Consolidated: **2 Low, 10 Info** (all Info items are
positive-analysis records, not defects).

The headline result: **the new explicit-value ETH accounting model was verified
sound by four independent agents** (general, precision-math, access-control, dos),
each attacking it from a different angle:

- **No `msg.value` double-spend.** `msg.value` is never read as an authorization
  amount; it simply lands in the balance. No `delegatecall`, no multicall-over-value.
- **The entry-balance check is arithmetically airtight.** `totalValue` accumulates
  under checked math (overflow reverts, covered by a regression test); for any
  bundle passing `sum ≤ balance`, every leg is provably solvent (prefix-sum
  argument), and mid-bundle ETH inflows only strengthen the guarantee.
- **No third-party griefing.** Both balance guards are one-directional
  (`> balance` reverts), and the only unauthenticated operation — depositing via
  `receive()` — can only *raise* the balance. No non-owner path reduces it. The
  new model is strictly more grief-resistant than the old exact-`msg.value` model.
- **No access-control regression.** All four mutating functions remain
  `onlyOwner nonReentrant`; `payable` adds no non-owner-reachable behavior; the
  transient guard blocks mid-bundle drains and cannot wedge sequential
  top-level calls batched in one transaction.

All first-audit fixes were re-verified in place: `evm_version = "cancun"` + the
default-deny Base-only chain allow-list (F-1); owner logging + zero-owner reject
(F-2); revert-reason bubbling in `execute`, `ZeroAmount` rejects, and the
`("memory-safe")` annotation (F-8, annotation confirmed legitimate at all three
`_bubbleRevert` call sites including the new `execute` path). Base mainnet and
Base Sepolia both support EIP-1153 (live since OP-Stack Ecotone, 2024-03-14), so
the transient guard is valid on both deploy targets.

### Consolidated findings

| ID | Title | Severity | Source |
|----|-------|----------|--------|
| SF-1 | Post-remediation doc regression: CLAUDE.md remediation sections deleted; stale REMEDIATION.md claims; dangling runbook pointer in deploy script; one-directional aliasing guidance | Low | spec-review, chain-specific (CS-1), standards-review |
| SF-2 | Deploy-time owner remains unverifiable against the *intended* value (accepted F-2 residual) | Low | access-control (AC-1) |
| SF-3 | Analysis records: new-model soundness notes and owner-self-inflicted micro-items | Info | all agents (G-1/G-2, PM-1/PM-2, E-1, ASM-1, AC-2, D-1/D-2) |

---

## Detailed Findings

### [SF-1] Post-remediation documentation regression (fix before deploy)
**Severity:** Low · **Location:** `CLAUDE.md`, `README.md`, `script/Executor.s.sol:36`, `docs/notes/deploy-to-base.md:29`, `audits/20.07.2026/REMEDIATION.md`

Commit `4aaed4f` ("trim CLAUDE.md deploy notes", the final commit before this
audit) deleted 102 lines from CLAUDE.md — including **all seven audit-finding
sections** that were the entire remediation deliverable for the
document/accept/exclude dispositions: "Owner verification (F-2)", "Deployment
address (F-6)", "Chain support and exclusions" (F-3), "Trust model (F-5)",
"Non-standard token withdrawals (F-4)", "Owner-self-inflicted DoS (F-7)", and
"Behavioral notes from F-8". Verified directly: the pre-trim CLAUDE.md had 9
finding references; the current file has 0. Consequences:

1. **REMEDIATION.md is now inaccurate.** It repeatedly claims documentation
   "in `CLAUDE.md`" (F-2 `:57-58`, F-3 `:71-72`, F-4 `:82-83`, F-5 `:100`,
   F-6 `:109`, F-7 `:123`) that no longer exists anywhere for F-3/F-5/F-6/F-7.
   F-2's runbook partially survives in `docs/notes/deploy-to-base.md`; F-4's
   NatSpec survives in `src/Executor.sol:182-190`.
2. **Dangling in-code pointer on an irreversible action.** `Executor.s.sol:36`
   says "see the owner-verification runbook in CLAUDE.md" — that runbook is no
   longer there; the actual runbook is `docs/notes/deploy-to-base.md`, which the
   comment never names. An operator following the code lands on the wrong file at
   the exact moment they set an immutable, unrecoverable value.
3. **One-directional aliasing guidance.** `deploy-to-base.md:29` warns only
   against "an address requiring L1→L2 aliasing"; it never covers the inverse —
   if the intended controller is an *L1 contract* driving the Executor via the
   Base deposit path, L2 `msg.sender` is the **aliased** address
   (`L1addr + 0x1111…1111`), so `OWNER` must be the aliased form or every
   `onlyOwner` call reverts forever.
4. **README warning stripped.** The F-5 audit recommendation "keep the README
   warning prominent" is no longer met — the README retains only "immutable
   owner", with no key-compromise/total-loss warning.

**Impact:** No on-chain effect. But the audit trail this deployment relies on now
overstates what is documented, and the two operational safeguards for the single
worst failure mode (wrong immutable owner → permanent loss of control) point to
the wrong place or cover only half the hazard.

**Recommendation:** Before deploying: (a) fix `Executor.s.sol:36` to reference
`docs/notes/deploy-to-base.md`; (b) make the aliasing note two-directional
(L2-native signer → raw address; L1-contract controller → aliased address);
(c) either restore condensed F-3/F-5/F-6/F-7 sections (in CLAUDE.md or the
runbook) or amend REMEDIATION.md to point at where each deliverable now lives;
(d) restore a one-line trust-model warning to the README.

### [SF-2] Deploy-time owner remains unverifiable against the *intended* value
**Severity:** Low (accepted residual of F-2) · **Location:** `script/Executor.s.sol:16-41`

The post-deploy `require(executor.OWNER() == owner)` compares the supplied value
to itself; a wrong-but-valid address (typo, or wrong aliasing form per SF-1.3) is
silently accepted and permanently unrecoverable. The on-chain
`owner.code.length > 0` guard was deliberately declined (consistent with F-5's
"no position on owner form"). The mitigating control is purely procedural —
verify the logged owner on a block explorer **before funding** — which makes
SF-1's runbook accuracy load-bearing. Optional belt-and-suspenders without
taking a position on owner form: require a second, independently supplied
`OWNER_CONFIRM` env var to match. See `findings-access-control.md` [AC-1].

### [SF-3] Analysis records (Info — no action required)

- **[G-1]** `bundleExecute` accepts empty no-op legs (`data.length == 0 && values[i] == 0`) that single `execute` rejects with `NoTransactionData` — cosmetic asymmetry.
- **[G-2] / [PM-2]** The entry sum-check conservatively rejects bundles fundable only via intra-bundle refunds — the deliberate price of precluding over-commit.
- **[PM-1]** Checked `totalValue` accumulation cannot silently wrap; do **not** `unchecked` it.
- **[E-1]** `withdrawERC20` emits `ERC20Withdrawn` without a balance-delta check; a token returning `true` while moving nothing yields a false-positive event (owner-chosen token; a delta check would break fee-on-transfer support).
- **[ASM-1] / [D-2]** `execute`'s new revert bubbling re-propagates unbounded owner-target returndata — a return-bomb primitive that is owner-self-inflicted only (F-7 class); `bundleExecute` remains immune (discards leg returndata).
- **[AC-2]** `nonReentrant` runs before `onlyOwner`, so a non-owner call touches the transient flag before rejection — zero impact (transient storage discards at tx end), micro style note.
- **[D-1]** Third-party deposits / mid-bundle balance changes cannot wedge execution; keep `receive()` unguarded (guarding it would break refund-routing bundles).

---

## Two-axis code review (`fd4e7ff...HEAD`)

**Standards axis — no hard violations.** Toolchain pins, licenses, custom-error
convention, and reentrancy coverage all conform to CLAUDE.md. Judgement calls
(smell baseline): divergent failure handling between `execute` (bubbles reasons)
and `bundleExecute` (discards; intentional per F-8 disposition); duplicated
triple-array setup across ~8 bundle tests; string-based error selectors in
`ExecutorScriptTest.t.sol:38,45` where siblings use compile-checked typed
selectors; test pragma pin inconsistency (`0.8.36` vs `^0.8.19` in siblings);
one inert mint in `testCannotWithdrawZeroERC20`.

**Spec axis — the contract delta is faithful.** All acceptance criteria of
issues #3 (single-execution stored/fresh ETH) and #4 (bundle spends available
ETH) are verifiably implemented and regression-tested; the F-8 fixes match their
tickets; the 74/74 test claim is accurate. The one substantive spec failure is
the documentation deletion consolidated as **SF-1**. Benign scope creep:
`[etherscan]` verify config, the deploy runbook, `AGENTS.md`, and committed
working notes — none asked for by an issue, none harmful.

---

## Positive Controls (verified sound this pass)

- New explicit-value accounting: solvency-proof per leg, checked sum, monotone
  deposit-only third-party surface, atomic rollback of stored+fresh ETH on
  failure (regression-tested).
- Transient reentrancy guard: correct on Base (EIP-1153 live since Ecotone),
  cannot wedge, safe under sequential same-tx batching, blocks mid-bundle drains.
- `("memory-safe")` on `_bubbleRevert`: legitimate at all three call sites; the
  block only reads within a Solidity-allocated buffer and terminates.
- Chain gating: default-deny allow-list (8453/84532), `evm_version = "cancun"`
  decoupled from toolchain bumps.
- Weird-ERC20 handling unchanged and correct (OZ SafeERC20 semantics); native
  USDC / bridged USDbC on Base withdraw cleanly; escape hatch intact and its
  NatSpec updated to the 3-arg `execute` form.

## Issue Filing

Per methodology, GitHub issues are filed for Medium+ findings only. **Nothing
reached Medium** — no issues filed. SF-1 is the one pre-deploy action item;
track it as a docs fix if desired.

## Recommended actions (prioritized)

1. **SF-1** — fix the dangling runbook pointer in `Executor.s.sol:36`, make the
   aliasing guidance two-directional, reconcile REMEDIATION.md/CLAUDE.md, restore
   the README trust warning. *(docs only; do before mainnet deploy because the
   owner-verification procedure is the sole safeguard for SF-2)*
2. **SF-2** — follow the verify-owner-on-explorer-before-funding procedure
   strictly; optionally add the `OWNER_CONFIRM` double-entry check.
3. Optional polish from the Standards axis (typed error selectors, test pragma
   consistency) — no security relevance.
