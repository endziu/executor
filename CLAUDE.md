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

## Code Conventions

- **Solidity Version**: 0.8.36 (pinned in foundry.toml, EVM target `osaka`). Track latest stable Foundry/solc; see the "Toolchain" section in README.md for the update/bump routine. CI installs the latest stable Foundry (`version: stable`).
- **License**: MIT for main contract and tests, UNLICENSED for the deploy script
- **Formatting**: Uses forge fmt (foundry formatter)
- **Security**: All state-changing functions include reentrancy protection
- **Access Control**: Owner-only pattern with `onlyOwner` modifier
- **Error Handling**: Custom errors preferred over require statements in main contract

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