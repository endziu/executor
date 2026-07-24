# Findings — Chain-Specific / L2 (second pass, pre-Base-mainnet)

**Scope:** `src/Executor.sol`, `script/Executor.s.sol`, `foundry.toml`, plus the
deploy docs (`docs/notes/deploy-to-base.md`, `CLAUDE.md`). Build: solc `0.8.36`,
`evm_version = "cancun"`, reentrancy guard via `transient` storage (EIP-1153),
plain CREATE deploy, custodies ETH + ERC20. Target networks (default-deny
allow-list): Base mainnet `8453`, Base Sepolia `84532`. Commit `4aaed4f`.

**Nature of this pass:** re-verification of the two fixed prior chain-specific
findings (F-1 osaka→cancun + chain allow-list; F-2 owner verification / L1→L2
aliasing docs) against the current code, plus a fresh walk of the checklist under
the *explicit-value* ETH accounting model that landed after the first audit. F-3
(zkSync) is excluded by policy and not re-litigated. Per this project's
severity-reconciliation convention, operator-controlled deployment/config choices
are rated Low/Info, not as attacker-reachable contract bugs.

---

## [CS-1] Owner-aliasing safeguard weakened by a dangling runbook reference and one-directional guidance
**Severity**: Low
**Category**: chain-specific
**Location**: `script/Executor.s.sol:36` (comment), `docs/notes/deploy-to-base.md:29`, `CLAUDE.md` "Deployment" section
**Description**: The F-2 remediation for the immutable-owner / L1→L2-aliasing hazard is a *documentation* control (the code deliberately declined an `owner.code.length > 0` assert, and rightly so — it takes no position on the owner's form). That control now has two integrity gaps that blunt it on an irreversible, unrecoverable action:

1. **Dangling cross-reference.** `Executor.s.sol:36` tells the operator to "see the owner-verification runbook in CLAUDE.md," but the aliasing/verification runbook content the F-2 remediation added to `CLAUDE.md` was subsequently trimmed (commit `4aaed4f`, "trim CLAUDE.md deploy notes"). CLAUDE.md's current Deployment section only says "verify the owner on a block explorer before funding" — it contains no L1→L2 aliasing note. The actual runbook now lives in `docs/notes/deploy-to-base.md`, which the code comment does not point to. An operator following the in-code pointer lands on the wrong file and may never see the aliasing guidance.

2. **One-directional aliasing guidance.** `deploy-to-base.md:29` instructs the operator to confirm the owner is "not an address requiring L1→L2 aliasing." That is correct for the expected case (an L2 EOA or L2 Safe as owner, where the raw address is used verbatim). It does **not** cover the inverse, legitimate case: if the intended controller is an **L1 contract** that will drive the Executor via the canonical bridge or an OP-Stack deposit transaction, then on Base the `msg.sender` seen by `onlyOwner` is the *aliased* address `L1addr + 0x1111000000000000000000000000000000001111`, so the operator would need to set `OWNER` to that aliased value. The guidance says only "avoid aliasing," leaving the L1-controller operator without the rule they need.

Why it matters: `OWNER` is immutable (`Executor.sol:18,75-78`) and the post-deploy `require(executor.OWNER() == owner)` (`Executor.s.sol:37`) is a tautology — it re-confirms the supplied value, never the *intended* form. A wrong-but-valid owner form is silently accepted and permanently bricks control of any funds sent to the contract. The only thing standing between the operator and that outcome is the runbook; a pointer that leads to the wrong file, plus guidance that omits the L1-contract case, erodes the sole safeguard.

Note on OP-Stack deposit txs specifically: aliasing applies only to L1 **contract** senders. An L1 **EOA** that force-includes a deposit transaction appears on L2 as itself (un-aliased), so an EOA owner is unaffected either way. The hazard is confined to the L1-contract-controller configuration, which is why this stays operator-config-Low, not High.

**Proof of Concept**:
- Operator intends to control the Executor from an existing L1 Safe/contract `C` via the Base bridge. They read `Executor.s.sol:36`, open `CLAUDE.md`, find only "verify on a block explorer," see nothing about aliasing, and set `OWNER = C` (raw L1 address).
- Deploy succeeds; `require(OWNER == C)` passes; Basescan shows `OWNER() == C`, which matches what the operator typed, so the Step-4 explorer check also passes.
- Operator funds the contract. Later, `C` sends an execution call through the Base `L1CrossDomainMessenger` / deposit path. On L2 the Executor sees `msg.sender == C + 0x1111…1111`, which `!= OWNER`, so `_checkOwner()` reverts `NotOwner`. Every `onlyOwner` path is now permanently unreachable; funds are frozen with no recovery (immutable owner, no upgrade).

**Recommendation**: Keep the documentation-only approach (consistent with F-5), but repair the two integrity gaps:
1. Fix the in-code pointer to name the file that actually holds the runbook:
   ```solidity
   // funding; see docs/notes/deploy-to-base.md ("Owner address decided").
   ```
2. Make the aliasing guidance two-directional in `deploy-to-base.md` (and mirror one line in CLAUDE.md's Deployment section so the two are not out of sync):
   > If the owner is an **L2** EOA or contract (the expected case), use its address verbatim. If the intended controller is an **L1 contract** driving the Executor via the Base bridge / a deposit transaction, `msg.sender` on L2 is aliased — set `OWNER` to `L1addr + 0x1111000000000000000000000000000000001111`. An L1 EOA sender is not aliased.

---

## Verified sound

The following checklist areas were walked against the current code and require no
finding. Items marked "re-verified" confirm a prior fix (F-1/F-2) holds in the
present source.

- **EIP-1153 transient storage on Base (the transient reentrancy guard).**
  `bool private transient locked` compiles to `TSTORE`/`TLOAD`. Base mainnet and
  Base Sepolia have supported these since the OP-Stack **Ecotone** upgrade
  (2024-03-14), which brought the Dencun/Cancun execution features (EIP-1153,
  EIP-5656 `MCOPY`, EIP-6780) to L2; `PUSH0` arrived earlier with **Canyon**. So
  every opcode a `cancun`-targeted solc 0.8.36 build emits is accepted on both
  target chains. The prior CS-1/F-1 bricking risk is inapplicable on the allow-listed
  networks. Transient storage is cleared at end-of-transaction per EIP-1153
  regardless of transaction type (including L1→L2 deposit txs), so the guard cannot
  wedge across txs. **Sound.**

- **`evm_version = "cancun"` + toolchain-decoupling (re-verifies F-1).**
  `foundry.toml:6` pins `cancun` — the minimum that satisfies the transient guard —
  and CLAUDE.md's Toolchain section now explicitly says to keep it pinned
  independently of solc bumps ("Raising the compiler target can emit bytecode that
  the supported Base networks do not yet accept"). This closes the earlier `osaka`
  over-targeting and the ratcheting concern. A `cancun` target will not emit
  Prague/Osaka opcodes (e.g. EIP-7939 `CLZ`), so no source-invisible opcode can slip
  onto Base. **Sound.**

- **Chain allow-list is default-deny and correct (re-verifies F-1).**
  `Executor.s.sol:24` reverts `UnsupportedChain(chainId)` for any chain other than
  `8453` / `84532` — deny-by-default, evaluated in `run(address)` which every entry
  path funnels through. Chain IDs are correct (Base mainnet 8453, Base Sepolia
  84532). `test/ExecutorScriptTest.t.sol` covers deploy-success on both allowed
  chains and revert on chain 1. This also enforces the F-3 zkSync exclusion by
  construction. **Sound.**

- **`block.chainid` / fork behavior.** The contract embeds no `block.chainid` in
  any signature, domain separator, or cached value — there is no EIP-712/permit,
  oracle, or replay surface. `block.chainid` is read only at deploy time by the
  script's allow-list gate, a one-shot check with no runtime consequence. A future
  Base fork that changed the chain ID could not corrupt any stored/signed value. A
  runtime chainid guard in the contract is unnecessary for an immutable,
  signature-free proxy. **Sound.**

- **Explicit-value ETH accounting on native-ETH L2 (post-first-audit model).**
  `execute(target,data,value)` and `bundleExecute` size spends against
  `address(this).balance` at entry. On Base, ETH is the native gas/value token
  (not a custom/ERC20 fee token as on some Orbit L3s), and — unlike Blast — held ETH
  does **not** rebase or accrue yield, so `address(this).balance` is stable between
  the check and the send. The `InsufficientBalance` guard and the bundle-sum check
  are therefore accurate on both target chains. `receive()` works normally on
  OP-Stack (no zkSync-style system-transfer caveat). Deposit-tx-minted L2 ETH simply
  raises the balance the same as any other credit. **Sound.**

- **L1 data fee / bundle sizing.** `bundleExecute`'s unbounded loop and
  owner-supplied calldata incur OP-Stack L1 data-availability fees (which can
  dominate total cost), and a very large bundle could approach the L2 block gas
  limit. Both are borne entirely by the owner inside an owner-initiated tx and are
  trivially routed around by splitting the bundle — the same owner-self-inflicted,
  no-third-party-impact class as prior F-7. No accounting or security impact.
  **Sound (no new finding).**

- **Sequencer / reorg / timing.** The contract has no oracle, liquidation,
  time-lock, `block.number`/`block.timestamp`/`prevrandao`, or finality-dependent
  logic, so Base sequencer downtime only delays owner transactions and OP-Stack's
  fixed `prevrandao` is never read. The CREATE nonce-based deploy address remains
  reorg-sensitive (prior F-6, documented in `deploy-to-base.md` — do not pre-fund a
  predicted address before finality); Base's single sequencer makes deep reorgs
  unlikely, and the runbook's "fund only after confirming on-chain `OWNER`" step
  already covers it. **Sound.**

- **Opcode / precompile portability.** No hardcoded infra, token, or precompile
  addresses; `*.code.length` guards rely only on standard `EXTCODESIZE`, which is
  EVM-equivalent on Base (the zkSync `EXTCODESIZE` caveat is excluded by the
  Base-only allow-list). **Sound.**

---

**Summary:** Low 1, Info 0. (Highest severity: CS-1 — owner-aliasing safeguard
weakened by a dangling runbook reference and one-directional guidance.) Prior F-1
and F-2 fixes re-verified present and correct in the current code; the transient
reentrancy guard and the `cancun`/explicit-value model are sound on both Base
targets.
