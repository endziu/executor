# Audit Remediation — `Executor`

Companion to [`AUDIT-REPORT.md`](./AUDIT-REPORT.md). That report is an immutable
record of the reviewed commit (`fd4e7ff`); this document records how each
consolidated finding **F-1 … F-8** was dispositioned, implemented, and verified.

- **Findings addressed:** 8 (2 with contract/config changes, the rest documented
  or accepted with rationale).
- **Remediation window:** 2026-07-20 – 2026-07-21.
- **Test suite:** 54/54 at audit time → **74/74** after remediation.
- **Tracking:** wayfinder epic
  [#5](https://github.com/endziu/executor/issues/5) and child tickets #6–#13
  (all closed).

Every disposition is one of **fix** (code/config change), **document**
(operational guidance, no behavior change), **accept** (intended design), or
**exclude** (out of scope by policy).

> **Amended 2026-07-22** (second-audit finding
> [SF-1](../21.07.2026/AUDIT-REPORT.md)): commit `4aaed4f` trimmed the CLAUDE.md
> deploy notes that originally held the F-2/F-3/F-5/F-6/F-7 documentation
> deliverables. Those deliverables now live in the deploy runbook,
> [`docs/notes/deploy-to-base.md`](../../docs/notes/deploy-to-base.md) (the
> F-3/F-5/F-6/F-7 notes under "Operational notes from the first audit"); F-4's
> escape-hatch documentation lives in the `withdrawERC20` NatSpec in
> `src/Executor.sol`. The location claims below have been updated to match.

## Summary

| ID | Title | Severity | Disposition | Commit |
|----|-------|----------|-------------|--------|
| F-1 | Deployment portability (`osaka` target, no chain guard) | Low | **Fixed** | [`692238d`](https://github.com/endziu/executor/commit/692238d) |
| F-2 | Deploy script doesn't verify the *intended* owner | Low | **Fixed + documented** | [`3c032fe`](https://github.com/endziu/executor/commit/3c032fe) |
| F-3 | zkSync Era / non-EVM-equivalent chains | Low | **Excluded + documented** | [`483b87c`](https://github.com/endziu/executor/commit/483b87c) |
| F-4 | Strict `_safeTransfer` blocks a few non-standard tokens | Low | **Documented** (escape hatch) | [`b7a0728`](https://github.com/endziu/executor/commit/b7a0728) |
| F-5 | Total centralization by design | Info | **Accepted + documented** | [`253b96f`](https://github.com/endziu/executor/commit/253b96f) |
| F-6 | CREATE deploy address is chain/reorg-dependent | Info | **Documented** | [`bf5a00c`](https://github.com/endziu/executor/commit/bf5a00c) |
| F-7 | Owner-self-inflicted DoS vectors | Info | **Accepted + documented** | [`3953b55`](https://github.com/endziu/executor/commit/3953b55) |
| F-8 | Minor consistency & cosmetic items | Info | **3 fixed, 3 accepted** | [`79d1eb1`](https://github.com/endziu/executor/commit/79d1eb1) |

## Findings

### F-1 — Deployment portability · **Fixed**

The transient-storage reentrancy guard compiles to `TSTORE`/`TLOAD` (EIP-1153,
Cancun+), and the build targeted `evm_version = osaka`, which strictly *narrows*
the safe chain set to Fusaka-class chains while adding no needed feature. There
was no deploy-time `chainid` guard.

**Fix:** pinned `evm_version = "cancun"` (the minimum that satisfies the transient
guard) and decoupled it from the toolchain-freshness routine; added a default-deny
chain allow-list to `script/Executor.s.sol` that reverts `UnsupportedChain` on any
chain other than Base mainnet (`8453`) or Base Sepolia (`84532`). Regression tests
cover deploy-success on both allowed chains and revert on an unsupported chain.

### F-2 — Deploy-time owner verification · **Fixed + documented**

`OWNER` is immutable; the post-deploy `require(executor.OWNER() == owner)` only
confirms the constructor stored the value it was given — it cannot detect a
*wrong-but-valid* address (a typo, or the raw L1 form where the L1→L2 **aliased**
form is required). Such a value is silently accepted and unrecoverable.

**Fix + docs:** the deploy script now logs the deployed address and resolved
`OWNER` for out-of-band verification, and a regression test asserts an
`OWNER=address(0)` input reverts `ZeroAddress`. An owner-verification runbook
(immutability/no-recovery warning, L1→L2 aliasing note for Base/OP-Stack,
verify-on-explorer-before-funding) lives in
[`docs/notes/deploy-to-base.md`](../../docs/notes/deploy-to-base.md), with a
condensed mirror in CLAUDE.md's Deployment section. Audit rec (a)
`owner.code.length > 0` was **deliberately declined** to stay consistent with the
F-5 disposition (the codebase takes no position on the owner's form).

### F-3 — zkSync Era / non-EVM-equivalent chains · **Excluded + documented**

zkSync Era is not EVM-bytecode-equivalent: it requires `zksolc` (this build
produces no zkSync artifact), its `EXTCODESIZE`/`code.length` semantics differ (so
the `code.length == 0` guards can false-positive), and its CREATE/CREATE2 address
derivation differs.

**Exclusion:** such chains are unsupported **by policy**, enforced by the F-1
Base-only allow-list (default-deny). No contract or script change; the rationale
and the "any chain added must be EVM-equivalent" rule are documented in
`docs/notes/deploy-to-base.md` ("Operational notes from the first audit"). The
existing unsupported-chain test covers the enforcement.

### F-4 — Strict `_safeTransfer` blocks a few non-standard tokens · **Documented**

`_safeTransfer` (OZ SafeERC20 semantics) treats a `false`/short/dirty return or a
call-revert as `ERC20TransferFailed`. As a side effect `withdrawERC20` rejects a
few legitimate non-standard tokens (return-`false`-on-success, `uint96`-capped,
zero-amount-revert). **No funds are ever locked.**

**Docs:** kept `_safeTransfer` strict (loosening it would silently accept genuine
failures) and documented the owner escape hatch in the `withdrawERC20` NatSpec
(`src/Executor.sol`):

```solidity
execute(token, abi.encodeCall(IERC20.transfer, (to, amount)), 0)
```

which only checks call-level success. The optional `amount == 0` reject was
deferred to F-8 (where it was implemented).

### F-5 — Total centralization by design · **Accepted + documented**

The owner can call any contract with any calldata/value and withdraw all held
assets; `OWNER` is immutable with no transfer/renounce/pause/timelock.

**Accepted** as the intended trust model for a single-owner personal execution
proxy — no third-party funds are induced or put at precondition-free risk. The
consequences (key compromise = total loss; key loss = permanent lockout;
third-party-sent assets become owner-controlled) are documented in
`docs/notes/deploy-to-base.md` ("Operational notes from the first audit") with a
prominent trust-model warning in the README. Custody of `OWNER` is left to the
operator; the codebase takes no position on its form (Safe vs EOA) and adds no
sweep mandate.

### F-6 — CREATE deploy address is chain/reorg-dependent · **Documented**

Plain `CREATE` derives the address from `keccak256(deployer, nonce)`, so it is
neither deterministic across chains nor reorg-stable.

**Docs:** a note in `docs/notes/deploy-to-base.md` ("Operational notes from the
first audit") records the caveats and operational guidance — don't
pre-fund a *predicted* address; deploy, wait for finality, read the actual address
from script output, then fund; reach for a `CREATE2` factory only if cross-chain
determinism is ever needed (not a current requirement). No code change.

### F-7 — Owner-self-inflicted DoS vectors · **Accepted + documented**

Four paths (unbounded bundle arrays, returndata copying, a reverting `balanceOf`
blocking `withdrawERC20`, a reverting ETH recipient blocking `withdrawEth`) can
consume excess gas or revert — but all are reachable **only inside an
owner-initiated tx with owner-chosen inputs**, and each has a recovery path. No
third party can trigger them.

**Accepted** as outside the threat model (consistent with F-5), with the reasoning
and recovery paths documented in `docs/notes/deploy-to-base.md` ("Operational
notes from the first audit"). The two optional hardenings from the
audit (a bundle-size cap and a `try/catch` around `balanceOf`) were **deliberately
declined** — arbitrary limit / added complexity on paths the owner can already
route around, no third-party benefit. `execute` hashing returndata into its event
and `bundleExecute` discarding return values are noted as existing positive
controls.

### F-8 — Minor consistency & cosmetic items · **3 fixed, 3 accepted**

**Fixed:**

- **`execute` swallowed the target's revert reason.** It now bubbles the reason
  via `_bubbleRevert` (mirroring the withdraw paths); an empty-data revert still
  falls through to `ExecutionFailed(0)`. `bundleExecute` keeps `ExecutionFailed(i)`
  — the failing leg's index is more useful in a batch than a raw reason.
- **Zero-amount withdrawals emitted phantom `*Withdrawn(0, …)` events.**
  `withdrawEth` and `withdrawERC20` now reject `amount == 0` with a new
  `ZeroAmount` error (this also closes the `amount == 0` item deferred from F-4).
- **`_bubbleRevert` lacked the memory-safe annotation.** Now
  `assembly ("memory-safe")` — the Yul was already provably correct; this is the
  current idiom.

**Accepted (no code change):**

- **`execute`/`bundleExecute` allow `target == address(this)`** while the withdraw
  functions reject `to == address(this)`. Not exploitable — a self-call into any
  mutating function reverts (`onlyOwner` sees `msg.sender == Executor`, not
  `OWNER`); blocking self-calls would contradict the general-purpose design.
- **Blocklist/pause tokens** (USDC/USDT) can freeze held balances at the token
  level — inherent counterparty risk, no in-contract mitigation.
- **ERC777/677 reentrant tokens** invoked via `execute` are fully contained by the
  transient reentrancy guard — a positive control.

New regression tests cover the bubbled reason, the empty-data fall-through, and
`ZeroAmount` on both withdrawals.

## Verification

- `forge build` clean; `forge test` **74/74** passing after remediation.
- Behavior-changing findings (F-1, F-8) carry targeted regression tests; the deploy
  script changes (F-1, F-2) are covered by `test/ExecutorScriptTest.t.sol`.
- `audits/AUDIT-REPORT.md` and the per-domain `findings-*.md` files are preserved
  unchanged as the historical audit record.
