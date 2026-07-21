# Findings — Chain-Specific / Multichain

**Scope:** `src/Executor.sol`, `foundry.toml`, `script/Executor.s.sol`. Build: solc `0.8.36`, `evm_version = osaka`, reentrancy guard via `transient` storage (EIP-1153), plain CREATE deploy, custodies ETH + ERC20.

> Auditor's note (added by synthesizer): the specialist's severities are preserved below. In the consolidated `AUDIT-REPORT.md` these are **recalibrated to Low** because they are operator-controlled deployment-configuration choices, not third-party-exploitable contract bugs — the contract is sound on its intended Cancun+ target. The *actionable* recommendations (prefer `cancun`, gate deploys, add a `chainid` check) stand regardless of label.

## [CS-1] Transient-storage reentrancy guard bricks every state-changing function on chains without EIP-1153
**Severity:** High (specialist) · **Location:** `Executor.sol:19` (`bool private transient locked;`), `_nonReentrantBefore/After` (`:50-57`), applied via `nonReentrant` to all four value-moving functions.

The guard compiles to `TSTORE`/`TLOAD` (EIP-1153), which exist only on Cancun+ chains. On a pre-Cancun chain they are invalid opcodes and revert. `_nonReentrantBefore` (a `TSTORE`) runs *before* the body, so every value-moving function reverts on entry, while unguarded `receive()` still accepts ETH — a contract that can be funded but never emptied. Immutable owner = no recovery. Silent: deploys/verifies fine, surfaces only on first withdrawal.

**EIP-1153 availability (re-verify per target):** Safe — Ethereum mainnet/Sepolia, Arbitrum One/Nova, OP Mainnet/Base + maintained OP-Stack, Polygon PoS, BNB, Gnosis, Scroll. Verify — new app-chains/forks pre-Cancun-equivalent, older testnets, Shanghai/Paris chains. zkSync — see CS-3.

**Recommendation.** Gate deploys on a scripted EIP-1153 probe + confirmed chain list; or, to target non-Cancun chains, replace the `transient` guard with a classic storage-slot guard.

## [CS-2] `evm_version = osaka` compiles bytecode only Fusaka-era chains accept
**Severity:** High (specialist) · **Location:** `foundry.toml:6`

`osaka` is the Fusaka EVM target (Ethereum mainnet only from end-2025). It is a superset of Cancun, so it does not help CS-1 and makes compatibility strictly worse — guaranteed only on Fusaka/Osaka-active chains (~mainnet in mid-2026). The contract needs no Osaka feature; its only post-Paris requirement is EIP-1153 (Cancun). The README's "track latest solc/Foundry" routine keeps ratcheting `evm_version` forward, silently dropping chains and potentially emitting Osaka-only opcodes (e.g. EIP-7939 `CLZ`) with no source change.

**Recommendation.** Set `evm_version = "cancun"` (minimum satisfying the transient guard). Decouple `evm_version` from the toolchain-freshness routine — pin to the oldest EVM all deploy targets support. Add `require(block.chainid == <expected>)` in the deploy script.

## [CS-3] zkSync Era incompatibility: toolchain, EXTCODESIZE semantics, CREATE derivation
**Severity:** Medium (specialist) · **Location:** `Executor.sol:99, 139, 179` (`*.code.length == 0` guards); build config; deploy script.

zkSync Era is not EVM-bytecode-equivalent: (1) needs `zksolc` — this build produces no zkSync artifact; (2) `EXTCODESIZE` differs (returns 0 for some system contracts / during construction), so the three `code.length == 0` guards can false-positive; (3) CREATE/CREATE2 address derivation differs from the EVM formula. **Recommendation.** Exclude zkSync (and non-EVM-equivalent zk chains), or maintain a separate zksolc build and re-audit the `code.length` guards under zkSync semantics.

## [CS-4] Nonce-based (CREATE) deployment address is chain- and reorg-dependent
**Severity:** Low (specialist) · **Location:** `script/Executor.s.sol:14`

Plain CREATE means address = f(deployer, nonce); no deterministic same-address-across-chains. On reorg-prone chains a re-mine changing nonce order lands the contract at a different address; pre-funding the predicted address before finality can strand funds. **Recommendation.** Don't pre-fund before finality; for deterministic cross-chain addresses use a CREATE2 factory with fixed salt; otherwise record the actual deployed address per chain after finality.

## [CS-5] Immutable owner + L1→L2 address aliasing can permanently lock out the owner
**Severity:** Low (specialist) · **Location:** `Executor.sol:18,75-78,67-69`; `script/Executor.s.sol:11`

On Arbitrum/OP-Stack, an L1 contract calling via the canonical bridge appears on L2 as the *aliased* sender (`L1addr + 0x1111…1111`). If control is intended from an L1 contract but `OWNER` is the raw L1 address, `onlyOwner` rejects every bridged call, and immutability makes it unrecoverable. **Recommendation.** Document per-chain which address form to use (aliased for L1-contract control on Arbitrum/OP-Stack; raw for EOA/L2-native); add a deploy-runbook check.

## [CS-6] Bridged / rebasing / dual-representation tokens (owner responsibility)
**Severity:** Info · **Location:** `Executor.sol:175-186`, `243`

`withdrawERC20` moves an owner-specified amount after a fresh `balanceOf` check, so it's robust to chain token quirks — noted for operators: native USDC vs bridged `USDC.e` (owner must pass the right address); USDT's per-chain bool/no-bool return already handled by `_safeTransfer`; rebasing/yield residuals accrue until swept. **Recommendation.** Operator docs should list correct per-chain token addresses; no code change.

## Checklist coverage
Not applicable (contract uses none): `block.number`/`block.timestamp`/`prevrandao`/block-time assumptions, OP-Stack L1-data-fee/fixed-gas stipends (all gas forwarded), sequencer-downtime/oracle staleness, hardcoded infra/precompile/token addresses, chainid-in-signatures (no EIP-712/permit). PUSH0 subsumed by CS-2 (fine on all Cancun+ chains).

## Summary (specialist)
High 2, Medium 1, Low 2, Info 1. Safe as-built only on post-Fusaka Ethereum mainnet; every current L2 (Arbitrum/Base/OP/Polygon/BNB/Scroll) is risky or bricked; zkSync out of scope for this toolchain. Minimal remediation: set `evm_version = "cancun"`, gate deploys on a verified EIP-1153 chain allow-list, add a `block.chainid` check.
