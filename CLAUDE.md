# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Foundry-based Solidity project implementing an `Executor` smart contract for secure execution of arbitrary contract calls. The contract provides owner-controlled transaction execution with reentrancy protection and asset management capabilities.

## Core Architecture

### Main Contract: `src/Executor.sol`
- **Purpose**: Secure execution proxy with ownership control
- **Key Features**:
  - Single transaction execution via `execute()`
  - Batch transaction execution via `bundleExecute()`
  - ETH and ERC20 token withdrawal functions
  - Reentrancy protection on all state-changing functions
  - Owner-only access control

### ETH accounting model
Outgoing call values are stated explicitly and are independent of `msg.value`:
- `execute(target, data, value)` sends `value` wei; `bundleExecute` sends each leg its own `values[i]`.
- Stored ETH and fresh `msg.value` are fungible. A call can be funded from stored balance (zero `msg.value`), fresh funding, or both. The requested value (or checked bundle sum) must not exceed the balance available at function entry, otherwise it reverts with `InsufficientBalance`.
- Excess funding stays deposited: any `msg.value` beyond what the call spends remains in the Executor and is not auto-forwarded. Direct ETH transfers land in the balance via `receive()`.
- The explicit-`value` signature is a breaking ABI change from the earlier exact-`msg.value` model. There is no in-place upgrade — deploy a new Executor and migrate assets with `withdrawEth` / `withdrawERC20`. Zero-value callers must pass an explicit `value` of `0`. Historical audit reports in `audits/` are annotated with this post-audit accounting change.

### Test Structure
The test suite is organized by functionality:
- `BaseExecutorTest.t.sol`: Base test contract with setup and helper contracts
- `ExecutorExecuteTest.t.sol`: Tests for single transaction execution
- `ExecutorBundleTest.t.sol`: Tests for batch transaction execution
- `ExecutorOwnerTest.t.sol`: Tests for ownership functionality
- `ExecutorBalanceTest.t.sol`: Tests for balance queries
- `ExecutorERC20Test.t.sol`: Tests for ERC20 token operations
- `ExecutorReceiveTest.t.sol`: Tests for ETH receiving functionality
- `ExecutorReentrancyTest.t.sol`: Tests for reentrancy protection

### Helper Contracts (in BaseExecutorTest.t.sol)
- `Target`: Simple contract for testing function calls
- `MockERC20`: ERC20 mock with configurable transfer failures
- `FailingTarget`: Contract that always reverts for error testing
- `ReentrantAttacker`: Re-enters the Executor from `receive()` and records the revert data
- `ETHRejectingContract` / `ETHRejectingWithReasonContract`: Reject incoming ETH (without/with reason)
- `RevertingERC20` / `EmptyRevertERC20`: Tokens whose `transfer` reverts (with/without data)
- `NoReturnERC20`: Non-standard token whose `transfer` returns no value

## Development Commands

### Building
```bash
forge build
```

### Testing
```bash
# Run all tests
forge test

# Run with verbose output (multiple levels)
forge test -v      # Basic
forge test -vv     # More verbose
forge test -vvv    # Most verbose

# Run specific test file
forge test --match-path test/ExecutorExecuteTest.t.sol

# Run specific test function
forge test --match-test testExecuteAsOwner

# Run tests with gas reporting
forge test --gas-report
```

### Other Foundry Commands
```bash
# Clean build artifacts
forge clean

# Generate documentation
forge doc

# Check gas usage
forge test --gas-report

# Generate coverage report
forge coverage
```

### Deployment
```bash
# OWNER env var sets the Executor owner (required)
OWNER=<OWNER_ADDRESS> forge script script/Executor.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

The deployment script accepts only Base mainnet (chain ID `8453`) and Base
Sepolia (chain ID `84532`). The contract uses EIP-1153 transient storage and is
compiled for Cancun, the minimum compatible EVM hardfork.

### Chain support and exclusions

The Executor targets EVM-bytecode-equivalent chains only, and the deploy-script
allow-list (default-deny) is the enforcement point. Any chain added to that list
must be EVM-equivalent.

**zkSync Era and other non-EVM-equivalent zk chains are unsupported (audit
finding F-3).** They are excluded by policy, not merely absent from the
allow-list, because:

- they require the `zksolc` compiler — this build produces no zkSync artifact;
- `EXTCODESIZE` / `code.length` semantics differ (e.g. `0` for some system
  contracts and during construction), so the `code.length == 0` guards in
  `execute` / `bundleExecute` / `withdrawERC20` can false-positive and reject
  legitimate targets or tokens;
- CREATE/CREATE2 address derivation differs from the EVM formula.

Supporting such a chain would require a separate `zksolc` build path and a
re-audit of the `code.length` guards under its semantics — out of scope here.

## Code Conventions

- **Solidity Version**: 0.8.36 (pinned in foundry.toml, EVM target `cancun`). Track latest stable Foundry/solc; see the "Toolchain" section below for the update/bump routine. CI installs the latest stable Foundry (`version: stable`).
- **License**: MIT for main contract and tests, UNLICENSED for the deploy script
- **Formatting**: Uses forge fmt (foundry formatter)
- **Security**: All state-changing functions include reentrancy protection
- **Access Control**: Owner-only pattern with `onlyOwner` modifier
- **Error Handling**: Custom errors preferred over require statements in main contract

## Toolchain

This project tracks the latest stable Foundry and solc. Versions are pinned in the
repo (`foundry.toml` `solc`, exact contract pragmas) so builds stay reproducible and
audit-safe; CI installs the latest stable Foundry automatically (`version: stable` in
`.github/workflows/test.yml`), so it needs no manual bump.

Keep `evm_version = "cancun"` pinned independently of solc upgrades. Raising the
compiler target can emit bytecode that the supported Base networks do not yet
accept even when the Solidity source itself is unchanged.

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

## Security Considerations

- The Executor contract can execute arbitrary calls, making owner security critical
- All external calls are protected by reentrancy guards
- Bundle execution validates ETH value totals match individual call values
- Bundle execution is atomic: any failed call or address(0) target reverts the whole bundle
- Ownership is immutable — key rotation means deploying a new Executor and migrating assets
- Withdrawal functions include balance checks before transfers

## Test Constants
- `OWNER`: address(0xabc) - Contract owner in tests  
- `ALICE`: address(0x1) - Test user
- `BOB`: address(0x2) - Test user
- `INITIAL_BALANCE`: 100 ether - Starting balance for test addresses

## Agent skills

### Issue tracker

Issues are tracked as GitHub issues (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default triage vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context (`CONTEXT.md` + `docs/adr/` at repo root). See `docs/agents/domain.md`.
