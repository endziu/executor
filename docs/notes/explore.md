# Executor as a balance-funded execution account

The Executor is no longer limited to forwarding ETH supplied with the current
owner transaction. It can spend ETH that was already deposited, combine stored
and freshly supplied ETH, and retain any unused amount for later work.

That change is more important than a convenience improvement. The Executor can
now hold native-asset working capital and use it across transactions. It is a
small, owner-controlled execution account rather than only a batching wrapper.

This note explores what that enables on Base, where the model is strongest, and
which apparent possibilities are still outside the current interface.

## The new execution model

[`Executor.execute`](../../src/Executor.sol) now takes three independent inputs:

```text
target        contract or ETH recipient
data          operation to perform
value         exact ETH to send to target
msg.value     optional ETH added to the Executor before the call
```

For an initial Executor balance `B`, fresh funding `F`, and requested call value
`V`, execution requires:

```text
V <= B + F
```

The target receives exactly `V`; it does not automatically receive `msg.value`.
Ignoring ETH returned by the target, the Executor finishes with `B + F - V`.
This supports four distinct operations through the same small interface:

| Operation | `msg.value` | `value` | Result |
| --- | ---: | ---: | --- |
| Spend stored ETH | `0` | `V` | Existing balance funds the call |
| Fund and spend | `F` | `V` | Stored and fresh ETH are fungible |
| Deposit while calling | `F` | `0` | Call executes and all fresh ETH remains |
| Top up a reserve | direct transfer | n/a | `receive()` adds to the balance |

`bundleExecute` applies the same distinction to every leg. It checks that the
sum of `values` does not exceed the balance available at bundle entry, then
performs the calls in order. If any leg fails, the complete transaction reverts,
including fresh funding and all earlier transfers.

Existing deployments are immutable and use their deployed bytecode. Adopting
this execution model requires deploying the new Executor ABI and migrating
assets from any old instance.

## What becomes possible

### 1. A pre-funded native-ETH strategy account

An Executor can keep a bounded amount of ETH as working capital. Its owner can
then perform payable protocol actions without sourcing and attaching the exact
ETH amount to every transaction.

This is useful when the funding source and operator are different:

```text
treasury / Safe / revenue source
              |
          periodic ETH
              v
        strategy Executor  <--- owner transaction from bot or Safe
              |
       payable protocol calls
```

The owner still pays the Base transaction's gas. The Executor balance funds
calls made *during* execution; it does not pay for the outer transaction. A bot
therefore needs enough ETH for gas, but it does not need custody of the strategy
principal in its EOA.

Possible jobs include payable mints, auction bids, collateral deposits, router
calls, protocol fees, and factory calls that deploy or initialize another
contract. Compatibility still depends on the called contract accepting a
contract caller and attributing the resulting position or asset to the intended
address.

### 2. ETH-to-WETH-to-protocol bundles

Base exposes WETH9 at
`0x4200000000000000000000000000000000000006` on both mainnet and Sepolia.
Stored ETH can fund an atomic flow such as:

1. Call `WETH9.deposit()` with stored ETH.
2. Approve the resulting WETH to a protocol.
3. Deposit, swap, or otherwise use the WETH.
4. Optionally revoke the approval.

The WETH minted by the first leg is immediately available to later legs, so the
whole workflow can be atomic. This makes native ETH usable in ERC-20-only
protocols without requiring an external account to wrap it first. See Base's
[official predeploy addresses](https://docs.base.org/base-chain/network-information/base-contracts).

The reverse direction needs more care. Calling `WETH9.withdraw()` can return ETH
to the Executor, but `bundleExecute` validates the sum of all outgoing ETH
values before any leg runs. Newly unwrapped ETH cannot generally fund a later
payable leg in that same bundle unless enough ETH was already present to pass
the initial check. It can be spent in a later transaction.

### 3. Mixed ETH and token rebalancing

A bundle can now coordinate native ETH and ERC-20 operations rather than using
ETH only as fresh transaction value. Examples include:

- Wrap stored ETH, approve WETH, and enter a token-denominated position.
- Spend stored ETH through a payable router and deposit the output token.
- Withdraw a token position, swap to ETH, and retain the ETH as working capital.
- Claim rewards, swap part of them, and send an ETH or token treasury split.
- Revoke temporary approvals before the transaction completes.

Tokens received by an earlier call can be used by later calls in the same
bundle. ETH received during a bundle is also retained, but the up-front
aggregate-value check limits its reuse inside that bundle. This asymmetry is the
main remaining restriction on complex native-asset pipelines.

### 4. Direct ETH distributions

A call with empty calldata may send stored ETH to an EOA. A bundle can therefore
perform atomic native-ETH distributions to multiple recipients:

- Contractor, contributor, or grant payouts.
- Treasury or revenue splits.
- Refund batches.
- Sweeps across operational accounts.
- An operator reimbursement included with a successful job.

Every amount is explicit in `values`, and a failed recipient reverts the whole
bundle. This is useful when all-or-nothing settlement is desired. It is a poor
fit when one rejecting recipient should not block everyone else; that requires
a pull-payment or best-effort distribution design.

### 5. Native ETH revenue and refund recycling

Anyone can send ETH to `receive()`, and payable targets can send empty-calldata
refunds back during execution. The Executor can accumulate:

- Protocol refunds and returned collateral.
- ETH-denominated fees or revenue.
- Residual ETH from overfunded owner calls.
- Intentional periodic treasury top-ups.

The next owner transaction can reuse that balance directly. This removes the
previous `withdraw -> fund owner -> call Executor again` round trip and keeps
capital inside the strategy address.

There is no deposit event or internal attribution. The balance is one fungible
pool, and the owner controls all of it regardless of who supplied it. This is
appropriate for treasury capital, but not for user deposits that require
per-user accounting or withdrawal rights.

### 6. Base-to-Ethereum ETH withdrawals

Stored ETH can initiate a native withdrawal through Base's bridge rather than
first being withdrawn to the owner. The L2 Standard Bridge at
`0x4200000000000000000000000000000000000010` exposes payable `bridgeETH` and
`bridgeETHTo` functions, so the Executor can make the initiating call with an
explicit value. See the [Base standard bridge
specification](https://docs.base.org/base-chain/specs/protocol/bridging/bridges).

The withdrawal is asynchronous and must still be proven and finalized on
Ethereum. An L2 withdrawal can target an L1 recipient other than the Executor's
same-address counterpart; the recipient and operational finalization process
should be chosen deliberately. See the [Base withdrawal
specification](https://docs.base.org/base-chain/specs/protocol/bridging/withdrawals).

### 7. A reusable settlement balance for automation

Automation becomes operationally simpler because each job does not need exact
just-in-time funding. A keeper can inspect the Executor balance, simulate a
bundle, and submit a transaction that consumes only the requested amount.
Unused fresh ETH stays available for the next job.

This enables recurring native-asset tasks, but it does not make the Executor a
trustless automation system. The owner can call any target with any calldata and
spend the complete balance. A compromised automation owner therefore compromises
all ETH and tokens held by that Executor.

The safe pattern is one narrowly funded Executor per strategy, with a Safe or a
purpose-built policy contract as owner when the balance is meaningful.

## High-value workflow patterns

### Pre-funded payable action

```text
deposit ETH once
      |
      v
execute(protocol, encodedAction, exactValue)
      |
      +-- protocol receives exactValue
      +-- unused balance stays in Executor
```

This is the simplest and strongest new capability.

### Wrap and deploy atomically

```text
WETH.deposit{value: x}()
        -> WETH.approve(protocol, x)
        -> protocol.deposit(x, Executor)
        -> WETH.approve(protocol, 0)
```

This works because later legs consume a token created by an earlier leg, while
the only outgoing ETH value (`x`) was available when the bundle began.

### Harvest into the operating reserve

```text
claim rewards
        -> swap rewards for ETH
        -> leave ETH in Executor
        -> spend it in a later owner transaction
```

This turns proceeds into future working capital without routing them through the
owner. Exact swap mechanics, recipient parameters, slippage limits, and
deadlines remain the caller's responsibility.

## What is still not possible

Balance-funded execution should not be confused with account abstraction or a
general smart-wallet feature set.

- **The Executor cannot pay its own outer transaction gas.** The transaction
  sender pays gas. There is no relayer, paymaster, or signed-intent interface.
- **A bot is not permission-limited.** Ownership is binary and immutable; there
  are no target allowlists, selector allowlists, value caps, balance floors,
  expiries, or session keys.
- **Mid-bundle ETH is not fully reusable.** The sum of all outgoing values must
  fit the entry balance, even if an earlier call unwraps WETH, receives a refund,
  or returns ETH that could economically fund a later leg.
- **The Executor has no general callback implementation.** Flash loans, swap
  callbacks, hooks, and protocols requiring a named receiver function cannot be
  supported merely by making an arbitrary outbound call. The reentrancy guard
  also prevents callbacks from re-entering `execute` or `bundleExecute`.
- **It cannot create contracts directly.** It can pay and call a factory, but
  there is no `CREATE` or `CREATE2` instruction exposed by its own interface.
- **It is not a multi-user vault.** Deposits are not attributed and create no
  claim against the Executor.
- **It is not yet a safe NFT account.** It lacks ERC-721 and ERC-1155 receiver
  callbacks, so safe transfers to it fail. Buying an NFT to the Executor is
  unsafe unless delivery semantics and recovery are explicitly verified.
- **Downstream safeguards are not added automatically.** Slippage, deadlines,
  recipient correctness, oracle checks, and approval scope must be encoded in
  the target calls.

## Security consequences of holding spendable ETH

The new behavior fixes a capability gap but increases the importance of the
Executor's balance as an explicit risk budget.

1. **Owner compromise now exposes native working capital immediately.** The
   owner can send stored ETH to an EOA with one call.
2. **A malicious or mistaken target can consume the exact value assigned to its
   leg.** It cannot directly pull more ETH, but arbitrary token approvals or
   subsequent owner calls can expose other assets.
3. **There is no enforced reserve.** Offchain policy may intend to retain 1 ETH,
   but the contract permits spending the full balance.
4. **Fresh and stored ETH are indistinguishable.** Sending excess `msg.value`
   intentionally tops up the Executor; sending it accidentally leaves it under
   owner control until withdrawn or spent.
5. **Simulation is important but not sufficient.** State and prices can change
   before inclusion. Protocol-level minimum outputs and deadlines are still
   required.

Operationally, the Executor should be treated as a hot strategy treasury. Fund
each instance only up to the loss limit appropriate for its owner and target
set.

## Design opportunities exposed by the new model

The current `execute` and `bundleExecute` interface remains small while hiding
funding, balance checking, ordered calls, and atomic rollback. That is a useful
deep module for a fully trusted owner. The next improvements should preserve
that compact interface and put policy behind it rather than forcing every
caller to reproduce safety checks.

### Allow balance recycling inside bundles

If atomic `unwrap -> payable action` or `receive ETH -> reuse ETH` workflows are
important, replace the aggregate entry check with a per-leg balance check just
before each call:

```text
for each leg:
    require(values[i] <= current Executor balance)
    call target with values[i]
```

This would allow ETH received by earlier legs to fund later ones while retaining
explicit per-call values and atomic rollback. It changes bundle semantics and
deserves dedicated tests for refunds, WETH unwraps, repeated use of returned ETH,
and failure at the first temporarily underfunded leg.

### Add policy for autonomous owners

For bot-controlled instances, the highest-leverage controls are:

- Allowed target and function-selector pairs.
- Per-call and per-period ETH spending limits.
- A minimum retained ETH balance.
- Token approval caps or mandatory approval revocation.
- Emergency pause and two-step owner rotation.
- Optional deadlines or operation nonces for signed jobs.

These controls would change the Executor from a trusted-owner module into a
policy-enforced execution module. They should be designed together; a target
allowlist alone is weak when an allowed router can transfer arbitrary assets to
arbitrary recipients.

### Improve observability and integration safety

Useful smaller improvements are:

- Emit a deposit event from `receive()` if funding history matters.
- Bubble target revert data, or include enough diagnostic information to make
  failed integrations actionable.
- Add ERC-721/ERC-1155 receiver and rescue support only if NFTs are in scope.
- Add Base deployment scripts that assert chain ID `8453` or `84532`.
- Change [`foundry.toml`](../../foundry.toml) from `osaka` to `cancun` so the
  configured EVM version states the actual Base-compatible minimum.
- Add Base fork tests for WETH wrapping and native bridge initiation.

## Recommended first use

The best first deployment is a narrowly funded native-ETH strategy Executor on
Base Sepolia, owned by a Safe or disposable automation key. Exercise these
flows before using meaningful value:

1. Deposit ETH separately, then spend only part of the stored balance.
2. Wrap stored ETH, approve WETH, perform a mock protocol action, and revoke the
   approval in one bundle.
3. Send a mixed ETH payout bundle and verify complete rollback on one failure.
4. Unwrap WETH and confirm that the returned ETH is available to a later
   transaction, including the current up-front bundle-check limitation.
5. Simulate an overfunded call and verify that the excess remains in the
   Executor rather than reaching the target.

The core opportunity is straightforward: the Executor can now keep capital and
act on it later. That makes it useful as a bounded strategy treasury, settlement
account, and native-asset automation account. Its strongest property remains
atomic arbitrary execution for a fully trusted owner; its largest remaining gap
is policy enforcement when that owner is an automated or otherwise hot key.
