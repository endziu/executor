# Executor

Secure execution of arbitrary contract calls by an authorized owner.

An owner can execute single transactions (with ETH), bundle multiple transactions
atomically (any failure reverts the whole bundle), and withdraw ETH/ERC20 balances.
All state-changing functions are reentrancy-protected. The owner is set at
deployment and is immutable.

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
(chain ID `84532`) only.

## Audit

The contract was reviewed in a multi-agent security audit
([`audits/AUDIT-REPORT.md`](audits/AUDIT-REPORT.md)). All eight consolidated
findings (F-1 … F-8) have been remediated — fixed, documented, accepted as
intended design, or excluded by policy — with the disposition and rationale for
each recorded in [`audits/REMEDIATION.md`](audits/REMEDIATION.md). No
high-severity issues were found; the two findings with code changes carry
regression tests.
