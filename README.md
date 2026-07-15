# Executor

Secure execution of arbitrary contract calls by an authorized owner.

## Overview

The Executor smart contract allows an owner to:
- Execute single transactions with ETH support
- Bundle multiple transactions atomically in a single call (any failure reverts the whole bundle)
- Manage ETH and ERC20 token balances
- Control access through ownership

## Ownership

The owner is set at deployment and is immutable — there is no ownership transfer.
To rotate the owner key, deploy a new Executor with the new owner and migrate
assets using `withdrawEth` / `withdrawERC20`.

## Installation

```bash
forge install
```

## Usage

### Building

```bash
forge build
```

### Testing

```bash
forge test
```

For verbose output:
```bash
forge test -vvv
```

### Deployment

The `OWNER` environment variable sets the Executor owner (required):

```bash
OWNER=<OWNER_ADDRESS> forge script script/Executor.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

## Toolchain

This project tracks the latest stable Foundry and solc. Versions are pinned in the
repo (`foundry.toml` `solc`, exact contract pragmas) so builds stay reproducible and
audit-safe; CI installs the latest stable Foundry automatically (`version: stable` in
`.github/workflows/test.yml`), so it needs no manual bump.

### Updating locally

```bash
foundryup           # update forge/cast/anvil to the latest stable
```

If `foundryup` reports itself out of date, update it first, then reinstall:

```bash
foundryup --update
foundryup --install stable
```

### Bumping solc

When a new solc release lands and you want to move to it, bump these three in lockstep,
then rebuild and test:

1. `foundry.toml` → `solc = "0.8.<new>"`
2. contract pragmas in `src/Executor.sol` and `script/Executor.s.sol` → `0.8.<new>`
3. `forge build && forge test`

> Note: because CI floats to `stable`, a new Foundry release can occasionally change a
> gas value or compiler default and turn CI red without any code change. If that
> happens, pin CI back to a known-good `version:` temporarily.
