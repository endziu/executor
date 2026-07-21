# Deploying Executor to Base

## Context

The `Executor` is an owner-controlled proxy that executes arbitrary calls and
holds ETH/ERC20 balances. The owner is **immutable and unrecoverable** — set once
in the constructor (`src/Executor.sol:75`) with a zero-address guard, and there is
no upgrade path (per CLAUDE.md, key rotation = redeploy + migrate). That makes the
deploy a high-consequence, one-shot action: a wrong owner address permanently
bricks control of any funds sent to the contract.

This runbook deploys via the existing `script/Executor.s.sol`, which only accepts
Base mainnet (`8453`) and Base Sepolia (`84532`) and asserts the stored owner
matches the supplied value. Chosen approach: **dry-run on Base Sepolia first, then
Base mainnet**, signing with a **hardware wallet / encrypted keystore** (no raw key
on disk), and **verifying source on Basescan**.

## Prerequisites

1. **Toolchain** — `foundryup` to latest stable; `forge build` is clean; `forge test` green.
2. **RPC endpoints** — a Base Sepolia and a Base mainnet RPC URL (Alchemy/QuickNode/`https://mainnet.base.org`).
3. **Basescan API key** — single Etherscan v2 key works for both Base networks (needed for `--verify`).
4. **Signer set up** — one of:
   - Ledger: connect, unlock, open Ethereum app (use `--ledger`).
   - Encrypted keystore: import the deployer key once with
     `cast wallet import base-deployer --interactive`, then reference `--account base-deployer`.
5. **Owner address decided and double-checked** — this is the single most important
   input. Confirm it is the *intended* controlling address (multisig/EOA), with the
   correct checksum, and in the correct aliasing form. It cannot be changed later.
   - If the owner is an **L2** EOA or contract (the expected case), use its address
     verbatim.
   - If the intended controller is an **L1 contract** driving the Executor via the
     Base bridge / an OP-Stack deposit transaction, the `msg.sender` seen on L2 is
     the **aliased** address — set `OWNER` to
     `L1addr + 0x1111000000000000000000000000000000001111`, or every `onlyOwner`
     call reverts forever. (An L1 **EOA** sender is *not* aliased and appears as
     itself.)
6. **Gas** — deployer EOA funded with a little ETH on each target network (Sepolia ETH from a faucet; real ETH on mainnet).

## Config (verification)

An `[etherscan]` section is present in `foundry.toml` so `--verify` resolves the
verifier for both chains:

```toml
[etherscan]
base = { key = "${BASESCAN_API_KEY}", chain = 8453 }
base_sepolia = { key = "${BASESCAN_API_KEY}", chain = 84532 }
```

Alternatively pass `--etherscan-api-key $BASESCAN_API_KEY` on the CLI. Keep
`evm_version = "cancun"` unchanged (required — the contract uses EIP-1153 transient
storage; CLAUDE.md warns not to raise the target).

## Step 1 — Deploy to Base Sepolia (dry run of the real flow)

Set env for the session (owner exported so the script's `vm.envAddress("OWNER")` resolves):

```bash
export OWNER=0x<INTENDED_OWNER>
export BASESCAN_API_KEY=<key>
export BASE_SEPOLIA_RPC=<sepolia rpc url>
```

Simulate first (no broadcast) to catch the `UnsupportedChain` guard and owner assert early:

```bash
forge script script/Executor.s.sol --rpc-url $BASE_SEPOLIA_RPC
```

Then broadcast + verify, signing with the chosen method:

```bash
# Ledger
forge script script/Executor.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --ledger --sender 0x<DEPLOYER_EOA> \
  --broadcast --verify

# — or — encrypted keystore
forge script script/Executor.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --account base-deployer --sender 0x<DEPLOYER_EOA> \
  --broadcast --verify
```

Record the logged `Executor deployed at:` and `Resolved OWNER` lines.

## Step 2 — Verify the Sepolia deploy end-to-end

- Open the deployed address on **sepolia.basescan.org**; confirm the source is
  verified (green check) and the contract compiled with solc 0.8.36 / cancun.
- Read `OWNER()` on the explorer (or `cast call <addr> "OWNER()(address)" --rpc-url $BASE_SEPOLIA_RPC`)
  and confirm it **exactly** equals the intended owner. This is the human check the
  script's `require` cannot do (a wrong-but-valid address still passes the assert).
- Optional smoke test: send a tiny amount of Sepolia ETH via `receive()`, then
  `withdrawEth` from the owner account to confirm control works before mainnet.

## Step 3 — Deploy to Base mainnet

Only after Step 2 passes. Same flow, mainnet RPC:

```bash
export BASE_RPC=<base mainnet rpc url>

# simulate
forge script script/Executor.s.sol --rpc-url $BASE_RPC

# broadcast + verify (Ledger example)
forge script script/Executor.s.sol \
  --rpc-url $BASE_RPC \
  --ledger --sender 0x<DEPLOYER_EOA> \
  --broadcast --verify
```

`OWNER` must still be exported and identical to the value validated on Sepolia.
Confirm the deployer prompt/Ledger screen shows the expected chain ID (8453) before approving.

## Step 4 — Post-deploy verification (mainnet)

- **basescan.org**: source verified, compiler/EVM version correct.
- `cast call <addr> "OWNER()(address)" --rpc-url $BASE_RPC` → **must equal the intended owner**.
- Do **not fund** the contract until the on-chain `OWNER` is confirmed. Immutable = no recovery from a typo.
- Save the broadcast artifact (`broadcast/Executor.s.sol/8453/run-latest.json`) and the
  deployed address for records.

## Notes / risks

- Immutability is the dominant risk — every guard here exists to catch a bad
  `OWNER` before funds move. The Sepolia round-trip is the cheap insurance.
- If `--verify` fails post-broadcast (indexing lag), re-run verification standalone:
  `forge verify-contract <addr> src/Executor.sol:Executor --chain <id> --etherscan-api-key $BASESCAN_API_KEY --constructor-args $(cast abi-encode "constructor(address)" $OWNER)`.
- Keep raw private keys out of the flow entirely; prefer Ledger/keystore as chosen.
- CI floats Foundry to `stable`; deploy from a locally pinned, tested toolchain and
  note the `forge --version` used for reproducibility.

## Operational notes from the first audit (F-3, F-5, F-6, F-7)

Condensed from the [first-audit dispositions](../../audits/20.07.2026/REMEDIATION.md).
This section is the durable home for these notes since the CLAUDE.md deploy notes
were trimmed (commit `4aaed4f`).

- **Chain exclusions (F-3).** Only Base mainnet (`8453`) and Base Sepolia
  (`84532`) are supported, enforced default-deny by the deploy script.
  Non-EVM-equivalent chains (e.g. zkSync Era: requires `zksolc`, different
  `EXTCODESIZE`/`code.length` semantics, different CREATE address derivation) are
  excluded by policy. Any chain ever added to the allow-list must be
  EVM-equivalent.
- **Trust model (F-5).** Total centralization by design: the immutable owner can
  call any contract with any calldata/value and withdraw all held assets. Key
  compromise = total loss of held assets; key loss = permanent lockout; assets
  sent by third parties become owner-controlled. The codebase takes no position
  on the owner's form (EOA vs Safe); key custody is the operator's
  responsibility.
- **Deployment address (F-6).** Plain `CREATE` derives the address from
  `(deployer, nonce)` — neither deterministic across chains nor reorg-stable.
  Never pre-fund a *predicted* address: deploy, wait for finality, read the
  actual address from the script output, then fund. Reach for a `CREATE2`
  factory only if cross-chain determinism is ever needed (not a current
  requirement).
- **Owner-self-inflicted DoS (F-7).** Unbounded bundle arrays, returndata
  copying, a reverting `balanceOf` blocking `withdrawERC20`, or an ETH-rejecting
  recipient blocking `withdrawEth` can burn gas or revert — but only inside an
  owner-initiated tx with owner-chosen inputs, and each has a recovery path
  (split the bundle, choose another recipient, use the `execute` escape hatch
  for non-standard tokens). No third party can trigger them. Accepted as outside
  the threat model.

## Verification checklist (summary)

- [ ] `forge test` green on the pinned toolchain
- [ ] `[etherscan]` config (or `--etherscan-api-key`) in place
- [ ] Sepolia: deployed, source verified, `OWNER()` == intended owner, optional withdraw smoke test
- [ ] Mainnet: simulate, broadcast on chain 8453, source verified
- [ ] Mainnet `OWNER()` confirmed on Basescan **before** funding
- [ ] Broadcast artifact + address archived
