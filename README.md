# Executor

Secure execution of arbitrary contract calls by an authorized owner.

An owner can execute single transactions (with ETH), bundle multiple transactions
atomically (any failure reverts the whole bundle), and withdraw ETH/ERC20 balances.
All state-changing functions are reentrancy-protected.

The owner is set at deployment and is **immutable** — there is no ownership transfer.
To rotate the owner key, deploy a new Executor and migrate assets with
`withdrawEth` / `withdrawERC20`.

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
