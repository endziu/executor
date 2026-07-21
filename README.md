# Executor

Secure execution of arbitrary contract calls by an authorized owner.

An owner can execute single transactions (with ETH), bundle multiple transactions
atomically (any failure reverts the whole bundle), and withdraw ETH/ERC20 balances.
All state-changing functions are reentrancy-protected. The owner is set at
deployment and is immutable.

> **Trust model:** a single, immutable owner controls all execution and every
> asset the contract holds. Compromise of the owner key means total loss of held
> assets; loss of the key means permanent lockout. There is no transfer,
> renounce, pause, or upgrade path.

## Install

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation):

```bash
foundryup            # install/update forge, cast, anvil
git clone https://github.com/endziu/executor && cd executor
forge build
```

## Usage

```bash
forge build          # build
forge test           # run tests (add -vvv for verbose)
```

Deploy (the `OWNER` env var sets the owner and is required):

```bash
OWNER=<OWNER_ADDRESS> forge script script/Executor.s.sol \
  --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

The deployment script supports Base mainnet (chain ID `8453`) and Base Sepolia
(chain ID `84532`) only. For the full deploy runbook — Sepolia dry-run first,
keystore/Ledger signing, and Basescan verification — see
[`docs/notes/deploy-to-base.md`](docs/notes/deploy-to-base.md).
