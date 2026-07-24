# Findings — Access Control & Centralization

**Target:** `src/Executor.sol`. Prior audit (`fd4e7ff`, L-1..L-4) excluded. `OWNER` immutability and absence of transfer/renounce/recovery are documented design constraints — assessed for residual risk, treated as by-design (Info).

## [AC-1] Immutable owner holds unrestricted arbitrary-call authority with no rotation, timelock, or multisig
**Severity:** Info (by design) · **Category:** access-control · **Location:** whole contract; `execute()`, `bundleExecute()`, `withdrawEth()`, `withdrawERC20()`; `OWNER` (`src/Executor.sol:18`)

**Description.** Owner can execute arbitrary calls with attached ETH and withdraw all ETH/ERC20. `OWNER` is `immutable`; no `transferOwnership`/`renounceOwnership`/timelock/pause/multisig. A compromised key drains every asset instantly with no on-chain mitigation. A lost key permanently strands assets — no rotation, only redeploy + manual migration. Intentional for a single-owner proxy and documented.

**Proof of Concept.** `execute(anyContract, calldata)` from `OWNER` runs any call; `withdrawEth(balance, attacker)` empties the contract. Both require only `msg.sender == OWNER`, so a stolen key suffices.

**Recommendation.** Deploy with a multisig/smart-account (Safe) as `OWNER` to dilute the single point of failure off-chain; keep the README warning prominent; hold no idle balances (sweep after use).

## [AC-2] Owner can seize any third-party assets sent to the contract
**Severity:** Info (by design) · **Category:** access-control · **Location:** `withdrawEth()` (`:154`), `withdrawERC20()` (`:175`), `receive()` (`:243`)

**Description.** `receive()` accepts ETH from anyone and the contract can receive ERC20s; any such funds become fully owner-controlled. For a personal execution proxy this is expected — no per-user accounting, no user deposits, so nothing induces third parties to deposit and there is no precondition-free third-party loss.

**Recommendation.** Document non-custodial nature; no code change required.

## [AC-3] Deploy-time owner is a single unverified env var binding an immutable role
**Severity:** Low · **Category:** access-control · **Location:** `script/Executor.s.sol:11-17`

**Description.** Owner comes from `vm.envAddress("OWNER")`. Being immutable with no recovery, a wrong-but-valid address permanently misassigns control. The script's `require(executor.OWNER() == owner)` catches a constructor/assignment mismatch but NOT an operator supplying the wrong `OWNER` value (it compares the wrong value to itself). Zero address is caught by the constructor.

**Proof of Concept.** `OWNER=0xTypo... forge script ...` deploys owned by an unintended-but-valid address; the post-deploy `require` passes because `OWNER()` equals the wrong supplied value. Immutability means no fix.

**Recommendation.** Assert the intended owner is a contract/multisig (`owner.code.length > 0`) or confirm the resolved owner before broadcast; prefer a Safe; add a runbook step to verify the owner on a block explorer post-deploy.

## Checklist coverage (verified sound)
- **Total upgradeability** — sound: no proxy, no `delegatecall`, no upgrade path.
- **Pausing blocks user ops** — N/A: no pause, no user operations.
- **Missing access controls** — sound: every state-changing external fn is `onlyOwner nonReentrant`; `getOwner`/`getBalance` read-only; `receive()` holds no privileged logic.
- **Self-call bypass via `execute(address(this),...)`** — sound: inner call has `msg.sender == address(this)` ≠ `OWNER` → reverts `NotOwner`; `nonReentrant` also blocks re-entry.
- **Two-step ownership transfer** — N/A: no transfer at all.
- **Functions operating on other users** — sound: no per-user state; withdrawal `to` validated vs `address(0)` and `address(this)`.
- **Whitelist bypass via proxy tokens** — N/A: no allow/deny lists.
- **Roles granted in constructor undocumented** — sound: sole `OWNER` role documented and re-asserted in deploy script.
- **Renounce bricks contract** — N/A: no `renounceOwnership`; constructor rejects zero.
- **Initializer callable by anyone** — sound: not upgradeable, no `initialize()`.
- **Multi-agent collusion** — N/A: single-role model.

## Summary
Critical 0, High 0, Medium 0, Low 1 (AC-3), Info 2 (AC-1, AC-2). No access-control bugs — all four state-changing functions correctly `onlyOwner nonReentrant`; the `execute(address(this), …)` self-call cannot escalate. Most important: AC-1 (Info, by-design) — recommend `OWNER` be a multisig. Only actionable code change is AC-3 (Low): harden the deploy script.
