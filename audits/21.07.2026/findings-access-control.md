# Findings — Access Control & Centralization (2nd pass, pre-Base-mainnet)

**Target:** `src/Executor.sol`, `script/Executor.s.sol`
**Toolchain:** solc 0.8.36, `evm_version = "cancun"`, EIP-1153 transient reentrancy guard, immutable `OWNER`
**Scope note:** Second audit before Base mainnet deploy. The mutating ABI changed since the
first pass — `execute(target, data, value)` now takes an **explicit value** parameter and both
`execute` and `bundleExecute` are `payable` with stored-ETH / `msg.value` fungibility. This
review re-verifies that the refactor introduced no access-control regression, and confirms the
F-2 (intended-owner) remediation. **F-5 (total centralization) is accepted by design and is not
re-reported.**

---

## [AC-1] Deploy-time owner remains unverifiable against an *intended* value beyond logging (F-2 residual)
**Severity**: Low
**Category**: access-control
**Location**: `script/Executor.s.sol:16-41` (`run()` / `run(address)`), constructor `src/Executor.sol:75-78`
**Description**: The F-2 remediation is in place and verified: the script now logs the deployed
address and the resolved `OWNER` (`Executor.s.sol:39-40`), carries an explicit NatSpec/comment
warning that the value is immutable and unrecoverable (`:32-36`), and the constructor rejects the
zero owner (`ZeroAddress`, `src/Executor.sol:76`). A runbook (immutability warning, L1→L2 aliasing
note for Base/OP-Stack, verify-on-explorer-before-funding) exists in `CLAUDE.md`. However, the
post-deploy `require(executor.OWNER() == owner, ...)` (`:37`) still only compares the supplied
value to itself, so a **wrong-but-valid** address (a typo, or the raw L1 form where the aliased
`L1addr + 0x1111…1111` is required to control the contract from an L1 owner) is silently accepted
and is **permanently unrecoverable** — every `onlyOwner` path reverts `NotOwner` forever and any
held assets freeze. The audit-recommended on-chain guard (`owner.code.length > 0`) was
deliberately declined to stay consistent with the F-5 "no position on owner form" disposition.
This is a documented, accepted operational risk, not a contract bug; residual Low.
**Proof of Concept**: `OWNER=0x<valid-typo> forge script script/Executor.s.sol --broadcast` on
chain 8453. The constructor stores the typo, `require(executor.OWNER() == owner)` passes (compares
the wrong value to itself), deployment "succeeds", and control is lost forever. No third party is
involved; the loss is operator-inflicted at deploy time.
**Recommendation**: No code change required if the accepted-risk posture stands. The mitigating
control is procedural and must be enforced in the deploy runbook: after broadcast, read the logged
`Resolved OWNER` line, paste it into a Base block explorer, confirm it is the intended
Safe/multisig, and **fund only after** that visual match. If a lightweight belt-and-suspenders
guard is ever wanted without taking a position on EOA-vs-contract, compare against a second
independently-supplied env var:
```solidity
// optional, deploy-time only
address expected = vm.envAddress("OWNER_CONFIRM");
require(owner == expected, "owner/confirm mismatch");
```

## [AC-2] Reentrancy guard is engaged before the owner check (modifier ordering)
**Severity**: Info
**Category**: access-control
**Location**: `execute()` `src/Executor.sol:90-95`, `bundleExecute()` `:130-135`, `withdrawEth()` `:164`, `withdrawERC20()` `:195`
**Description**: All four mutating functions list `nonReentrant` **before** `onlyOwner`, so on a
call from a non-owner `_nonReentrantBefore()` sets the transient `locked` flag *before*
`_checkOwner()` reverts `NotOwner`. This has **zero security impact**: the whole transaction
reverts, and EIP-1153 transient storage is discarded at end-of-transaction, so the guard can never
wedge and a rejected non-owner call leaves no residue. It is a micro best-practice note only —
authorization is conventionally checked before any state (even transient state) is touched, and it
fails marginally cheaper for the reverting caller.
**Proof of Concept**: None (no exploitable condition). ALICE calls `execute(...)`: `locked` is set
true, `_checkOwner` reverts `NotOwner`, the tx unwinds, `locked` resets. Subsequent owner calls
are unaffected.
**Recommendation**: Optional. If reordered to `onlyOwner nonReentrant`, place `onlyOwner` first so
authorization gates entry before the guard engages. Safe to leave as-is.

---

## Verified sound

Walked against the access-control checklist (centralization, privilege escalation, role
management, initialization/deployment, multi-agent). Everything below is clean:

- **No missing access control on any mutating path** (checklist #6). Every state-changing external
  function carries `onlyOwner nonReentrant`: `execute` (`:90-95`), `bundleExecute` (`:130-135`),
  `withdrawEth` (`:164`), `withdrawERC20` (`:195`). `_checkOwner` reverts `NotOwner` unless
  `msg.sender == OWNER` (`:67-69`). No new function, internal-turned-external path, or fallback was
  introduced by the payable refactor.
- **The payable + explicit-value refactor cannot be abused by a non-owner.** `execute`/
  `bundleExecute` being `payable` only matters for a caller who passes `onlyOwner` — a non-owner
  cannot reach the body at all. The only unauthenticated ETH-entry is `receive()` (empty,
  `:264`); a third party can *add* to the balance but never spend it, withdraw it, or invoke any
  logic. Because both entry checks are `value > address(this).balance` (`:103`) and
  `totalValue > address(this).balance` (`:145`), an attacker depositing ETH can only *loosen* the
  bound, never make a legitimate owner call revert — so there is no deposit-griefing / balance-
  manipulation DoS. There is no per-user accounting to corrupt. Owner control over
  third-party-deposited ETH is the accepted F-5/AC-2 trust model, not a new issue.
- **Front-running / deploy race** (checklist #14). `OWNER` is a constructor argument set by the
  deployer's own transaction; there is no post-deploy `initialize()` (see below) and thus no owner-
  claim window an attacker could front-run. CREATE-address / reorg caveats are the previously-
  documented F-6 (out of access-control scope).
- **`receive()` holds no privileged logic** (`:264`) — it cannot change owner, move assets, or set
  the guard; it only credits the balance.
- **View functions leak nothing sensitive** — `getOwner()` (`:213`) returns the already-public
  immutable `OWNER`; `getBalance()` (`:221`) returns on-chain-observable `address(this).balance`.
  No private key material, nonce, or guard state is exposed.
- **Self-call escalation is impossible** (checklist #8). `execute`/`bundleExecute` permit
  `target == address(this)`, but an inner re-entry sees `msg.sender == address(this) != OWNER`
  (reverts `NotOwner`) and is independently blocked by the transient guard.
- **No upgradeability / delegatecall / initializer surface** (checklist #3, #13). No proxy, no
  `delegatecall`, no `initialize()`; `_disableInitializers()` is N/A. Nothing for an attacker to
  initialize or upgrade.
- **Ownership rotation primitives absent by design** (checklist #7, #12). No `transferOwnership`
  (single-step footgun N/A) and no `renounceOwnership` (cannot be bricked to zero owner). `OWNER`
  is immutable and non-zero — key rotation is redeploy-and-migrate, documented.
- **Role management** (checklist #10, #11, #15). Exactly one role (`OWNER`), granted in the
  constructor and documented in NatSpec + deploy script; no unbounded role grants, no multi-role
  collusion surface.
- **Admin-token-transfer rug vector** (checklist #1) — the withdraw functions are owner-only and
  the design is explicitly a single-owner proxy with no third-party user deposits induced; this is
  F-5 (accepted), not a rug of external users.
- **Timelock / pause** (checklist #2, #4) — N/A; no user-facing parameters, no pause that could be
  weaponized against withdrawals.
- **Deploy script access surface.** The `public executor` state var and the `run(address)` public
  overload live only in the `forge script` contract (`Executor.s.sol:11, 23`) — never deployed to
  chain, so they expose no on-chain entry point. The chain allow-list (`:24-26`, Base 8453 /
  Base Sepolia 84532 only, default-deny) remains in force.

---

**Summary:** Critical 0, High 0, Medium 0, Low 1 (AC-1), Info 1 (AC-2). No access-control
vulnerabilities. The payable / explicit-value refactor introduced no regression — all four
mutating functions remain `onlyOwner nonReentrant`, no non-owner path exists, and depositing ETH
cannot grief the owner. F-2 remediation (logging + runbook + zero-owner reject) verified in place;
AC-1 is its documented, accepted residual.
