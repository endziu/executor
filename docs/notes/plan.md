# Implementation plan: allow stored ETH to fund executions

## Objective

Redesign call-value accounting so `Executor` can fund arbitrary calls from:

- ETH already held by the contract.
- Fresh `msg.value`.
- A combination of both.

The key invariant should be:

```solidity
total outgoing ETH <= address(this).balance
```

At function entry, `address(this).balance` already includes the current call's
`msg.value`.

## Assumptions

- Breaking the `execute` ABI is acceptable because this change is intended for
  a new deployment.
- Excess `msg.value` is retained by the Executor as deposited ETH.
- Existing ownership and reentrancy behavior must remain unchanged.
- ERC-20 execution behavior is out of scope.

## Contract changes

Modify `src/Executor.sol`.

### 1. Give `execute` an explicit outgoing value

Change the signature from:

```solidity
execute(address target, bytes calldata data)
```

to:

```solidity
execute(address target, bytes calldata data, uint256 value)
```

Do not derive outgoing value from `msg.value`.

Change:

```solidity
if (msg.value == 0 && data.length == 0) revert NoTransactionData();
```

to:

```solidity
if (value == 0 && data.length == 0) revert NoTransactionData();
```

Before the external call, validate:

```solidity
if (value > address(this).balance) revert InsufficientBalance();
```

Execute the call using:

```solidity
target.call{value: value}(data);
```

This must support a bare stored-ETH transfer to an EOA when `data` is empty and
`value` is nonzero.

### 2. Change bundle accounting

Keep the existing `values` array and checked calculation of `totalValue`.

Replace:

```solidity
if (totalValue != msg.value) revert IncorrectEthValue();
```

with:

```solidity
if (totalValue > address(this).balance) {
    revert InsufficientBalance();
}
```

Do not require `totalValue` to equal `msg.value`.

Each bundle leg should continue forwarding exactly `values[i]`.

### 3. Remove the obsolete error

Remove `IncorrectEthValue` if it is no longer used anywhere:

```solidity
error IncorrectEthValue();
```

Use the existing `InsufficientBalance` error for both single and bundled
execution.

### 4. Improve event accounting

Recommended event changes:

```solidity
event Executed(
    address indexed target,
    uint256 value,
    bytes data,
    bytes32 resultHash
);

event BundleExecuted(
    address[] targets,
    uint256[] values,
    bytes[] data
);
```

Emit the requested outgoing values, not `msg.value`. Update event declarations
duplicated in test contracts.

## Required semantics

The implementation should exhibit these behaviors:

| Existing balance | `msg.value` | Requested value | Result |
| ---: | ---: | ---: | --- |
| 2 ETH | 0 | 1 ETH | Send 1 ETH; retain 1 ETH |
| 0 | 1 ETH | 1 ETH | Send 1 ETH |
| 1 ETH | 1 ETH | 1.5 ETH | Send 1.5 ETH; retain 0.5 ETH |
| 1 ETH | 1 ETH | 0.5 ETH | Send 0.5 ETH; retain 1.5 ETH |
| 1 ETH | 0 | 2 ETH | Revert `InsufficientBalance` |

The same rules apply to the sum of bundle values.

## Test changes

Update `test/ExecutorExecuteTest.t.sol` for the new argument. Existing
zero-value calls should pass `0`.

Add tests for:

1. `execute` spends entirely from stored ETH.
2. `execute` spends from stored ETH plus fresh `msg.value`.
3. `execute` retains excess fresh `msg.value`.
4. `execute` reverts when `value > address(this).balance`.
5. Stored ETH can be transferred to an EOA with empty calldata.
6. `value == 0` and empty calldata still reverts.
7. Supplying `msg.value` does not automatically forward it when explicit
   `value` is zero.
8. A failed target call rolls back both stored-balance spending and fresh
   funding.

Update `test/ExecutorBundleTest.t.sol`.

Replace the incorrect-total-value test with tests proving:

1. A bundle can be funded entirely from stored ETH.
2. A bundle can combine stored ETH and `msg.value`.
3. A bundle may spend less than `msg.value`, retaining the remainder.
4. A bundle reverts with `InsufficientBalance` when the sum exceeds the
   available balance.
5. Each target receives exactly its corresponding `values[i]`.
6. A failed bundle leg rolls back all earlier transfers and state changes.
7. Zero-value bundles continue working.
8. The sum calculation remains checked against overflow.

Update event expectations if event signatures change.

## Documentation updates

Update:

- `docs/notes/explore.md`
- `README.md`
- Any audit notes that describe `totalValue == msg.value`

Document clearly that:

- `msg.value` funds the Executor but does not determine outgoing value.
- `execute.value` and `bundleExecute.values` determine outgoing ETH.
- Stored and fresh ETH are fungible once received.
- Excess `msg.value` remains in the Executor.
- A user who only wants to deposit ETH can call `receive()` directly.
- Existing deployed contracts cannot gain this feature; a new Executor must be
  deployed and assets migrated.

Do not rewrite historical audit reports as though the old analysis were
incorrect. If those reports are intended as immutable records, add a note that
the accounting model changed after the report instead.

## Verification

Run:

```bash
forge fmt --check
forge build
forge test
```

Then inspect for stale assumptions:

```bash
rg "IncorrectEthValue|totalValue.*msg.value|value: msg.value|fresh.*msg.value" \
  src test docs README.md audits
```

## Acceptance criteria

The work is complete when:

- A zero-`msg.value` call can spend stored ETH.
- Single and bundled execution reject aggregate outgoing value above the
  available balance.
- Exact per-call values are forwarded.
- Excess funding remains in the Executor.
- Existing access control, codeless-target validation, atomic bundle rollback,
  and reentrancy protection still pass.
- The full Foundry test suite passes.
