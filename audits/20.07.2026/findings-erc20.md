# Findings — Weird ERC20 Tokens

**Structural fact shaping every verdict:** the Executor keeps **no internal accounting** — no share/vault math, no cached balances, no `totalSupply` pricing, no `decimals()` reads, no credited deposit amounts. `withdrawERC20` reads `balanceOf(address(this))` live immediately before each transfer. This neutralizes the majority of the weird-token class because no stored number can drift from reality.

**Result:** Critical 0, High 0, Medium 0, Low 1 (E-1), Info 2 (E-2, E-3). Prior-fix items from `fd4e7ff` (short-return, codeless-target, self-send, event bomb) excluded.

## [E-1] Non-standard tokens can block `withdrawERC20`, but funds remain recoverable via `execute`
**Severity:** Low · **Location:** `withdrawERC20` (`:175-186`), `_safeTransfer` (`:210-228`)

`_safeTransfer` intentionally treats a `false` return, short/dirty return, or call-level revert as `ERC20TransferFailed`. Correct for safety, but it blocks the dedicated withdrawal path for several legitimate-but-weird tokens:
- **Return-false-despite-success** (Tether Gold class): reverts on `false`, rolling back the transfer — no loss, but withdrawal always reverts.
- **Zero-amount-revert** (LEND, some BNB): `withdrawERC20(token, 0, to)` passes the `balanceOf < 0` check (0 is never `<` a balance) then hits `transfer(to, 0)`, which reverts.
- **uint96-capped** (UNI, COMP): `amount > type(uint96).max` reverts inside the token (only reachable if the contract holds > 2^96−1 base units).
- **Blocklisted `to`** (USDC/USDT): reverts; owner picks another `to`.

None is a loss of funds or state corruption. Owner always has an escape hatch: `execute`/`bundleExecute` can call `token.transfer(to, amount)` directly and ignore the return, since `execute` only checks call-level `success`. Impact is per-token usability on the convenience function, not custody risk.

**Proof of Concept.** Contract holds 1000 units of a `false`-returning token → `withdrawERC20(token, 1000, owner)` reverts `ERC20TransferFailed`. Owner calls `execute(token, transfer(owner, 1000))` — raw call succeeds; funds recovered.

**Recommendation.** Accept strict `_safeTransfer` as the right default; document in `withdrawERC20` NatSpec that non-compliant tokens should be withdrawn via `execute`. Optionally reject `amount == 0` in `withdrawERC20` for a clear error.

## [E-2] Blocklist / global-pause tokens can permanently freeze held balances (inherent, unmitigable)
**Severity:** Info · **Location:** `withdrawERC20` (`:175-186`)

For admin-controlled tokens (USDC, USDT, cUSDC), the issuer can blocklist the Executor's own address or globally pause transfers; `transfer` then reverts and the held balance is unwithdrawable. Ownership is immutable and there is no alternate custody path — standard counterparty risk of holding centralized-admin tokens, not a defect. `execute` provides no escape (the freeze is enforced token-side against the holding address). **Recommendation:** operationally avoid parking large balances of admin-pausable tokens long-term; note redeploy-based key rotation does not unfreeze a blocklisted old address.

## [E-3] Reentrant tokens (ERC777 / ERC677) are fully contained by the transient reentrancy guard
**Severity:** Info · **Location:** `nonReentrant` (`:44-57`) and all four state-changing entry points

Arbitrary `execute`/`bundleExecute` calls could let a malicious ERC777 (`tokensReceived`/`tokensToSend`) or ERC677 (`transferAndCall`) token attempt re-entry. All four state-changing functions share one `nonReentrant` guard backed by a `transient` lock held for the entire outer call — including across the whole `bundleExecute` loop — so any callback reverts with `ReentrancyGuard`. With no internal balances to manipulate mid-call, there is no read-only-reentrancy surface either. **Recommendation:** none; guard design is sound.

## Checklist coverage (34 items walked)
Value-corruption class (fee-on-transfer, rebasing, decimals, flash-mint, high-decimal overflow, max-amount sentinel) — **N/A / Safe**: no internal accounting, live `balanceOf`, no price/rate multiplication, no `decimals()`/`name`/`symbol` reads. Return-value handling (USDT no-return, bool tokens, Solmate codeless silent-success) — **covered** by `_safeTransfer` + `token.code.length > 0` check. Approvals/permit (USDT race, BNB zero-approve, DAI permit, phantom permit, front-run) — **N/A**: no internal `approve`/`permit`/`transferFrom`. Max-amount sentinel (cUSDCv3) — **inadvertently defended**: `balanceOf(this) < type(uint256).max` reverts. Reentrancy (ERC777/677) — **contained** (E-3). Blocklist/pause — **E-2**. False-return/zero-amount/uint96 — **E-1**.

## Summary
No High/Critical/Medium ERC20 issues. No-internal-accounting design plus prior `_safeTransfer` hardening removes the value-corruption class. Only actionable item is E-1 (Low) — document the `execute` escape hatch and optionally reject `amount == 0`.
