# Executor

Secure execution of arbitrary contract calls by an authorized owner.

An owner can execute single transactions (with ETH), bundle multiple transactions
atomically (any failure reverts the whole bundle), and withdraw ETH/ERC20 balances.
All state-changing functions are reentrancy-protected.

The owner is set at deployment and is **immutable** — there is no ownership transfer.
To rotate the owner key, deploy a new Executor and migrate assets with
`withdrawEth` / `withdrawERC20`.

## ETH accounting

Outgoing call values are stated explicitly and are independent of `msg.value`:

- `execute(target, data, value)` sends `value` wei to the target;
  `bundleExecute` sends each leg its own `values[i]`.
- Stored ETH and fresh `msg.value` are **fungible**. A call can be funded
  entirely from the Executor's stored balance (send zero `msg.value`), from
  fresh funding, or from both. The requested value (or checked bundle sum) must
  not exceed the balance available at function entry, otherwise the call reverts
  with `InsufficientBalance`.
- **Excess funding stays deposited.** Any `msg.value` beyond what the call spends
  remains in the Executor; it is not auto-forwarded. Sending `msg.value` with an
  outgoing value of zero simply deposits it.
- You can also fund the Executor directly — plain ETH transfers land in its
  balance via `receive()`.

The explicit-`value` signature is a **breaking ABI change** from the earlier
exact-`msg.value` model. There is no in-place upgrade: deploy a new Executor and
migrate assets with `withdrawEth` / `withdrawERC20`. Zero-value callers must pass
an explicit `value` of `0`.

## Usage

```bash
forge build          # build
forge test            # run tests (add -vvv for verbose)
```

Deploy (the `OWNER` env var sets the owner and is required):

```bash
OWNER=<OWNER_ADDRESS> forge script script/Executor.s.sol \
  --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

The deployment script supports Base mainnet (chain ID `8453`) and Base Sepolia
(chain ID `84532`) only, and rejects every other chain before broadcasting. The
contract uses EIP-1153 transient storage and is compiled for the Cancun EVM, the
minimum hardfork required by its reentrancy guard.

## Toolchain

Tracks the latest stable Foundry/solc, with versions pinned (`foundry.toml`,
contract pragmas) for reproducible builds. The EVM target remains pinned to
`cancun` independently of compiler upgrades. CI floats to `stable`. See
CLAUDE.md for the local update and solc-bump routine.
