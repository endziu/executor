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
assets using `withdrawETH` / `withdrawERC20`.

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
