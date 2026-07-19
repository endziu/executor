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

## Toolchain

Tracks the latest stable Foundry/solc, with versions pinned (`foundry.toml`,
contract pragmas) for reproducible builds. CI floats to `stable`. See CLAUDE.md
for the local update and solc-bump routine.
