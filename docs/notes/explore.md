# Using Executor on Base

This repository is a compact, owner-controlled execution account. It is deployable on Base, but it is best used as a specialized treasury or strategy executor—not as a full smart wallet or trustless automation protocol.

## What the repository currently provides

[`src/Executor.sol`](src/Executor.sol) implements:

- Arbitrary owner-authorized contract calls.
- Atomic batches where every call succeeds or the entire batch reverts.
- ETH and ERC-20 custody and withdrawal.
- A transient-storage reentrancy guard.
- Immutable ownership.
- No upgradeability, signatures, relayers, permissions, timelocks, or protocol-specific logic.

The implementation is small and reasonably defensive. All 54 tests pass, including reentrancy, atomicity, unusual ERC-20, ETH-transfer, and access-control tests.

## Base compatibility

It works on Base today:

- Base is an EVM-compatible L2 with chain ID `8453`; Base Sepolia is `84532`. See the [Base network documentation](https://docs.base.org/base-chain/quickstart/connecting-to-base).
- The contract uses `TLOAD`, `TSTORE`, and `MCOPY`. Base received these Cancun features through the OP Stack Ecotone upgrade. See the [OP Stack Ecotone specification](https://specs.optimism.io/protocol/ecotone/overview.html).
- A contract execution test passed against a live Base-mainnet fork on July 19, 2026.

One qualification: [`foundry.toml`](foundry.toml) targets `osaka`. The current bytecode happens to use only Cancun-era special opcodes, so it works, but this should be changed to `cancun`. That states the real minimum requirement and prevents a future compiler version from emitting a newer opcode unsupported by Base.

The repository's audit report overstates this point when it suggests the current artifact is effectively Ethereum-mainnet-only. Inspection of the artifact and a live Base fork test demonstrate otherwise.

## Best Base use cases

### 1. Isolated DeFi strategy account

This is the strongest fit.

Deploy one Executor per strategy and fund it with only the tokens that strategy may use. A bot, Safe, or other controlling account becomes `OWNER`.

Example atomic bundle:

1. Approve USDC to a lending pool.
2. Supply USDC.
3. Enable collateral or perform another protocol action.

Aave V3 has an official Base deployment, making supply, withdraw, borrow, and repay workflows an obvious integration. See [Aave deployments](https://aave.com/help/aave-101/accessing-aave).

This gives useful isolation: compromise of one strategy owner exposes that Executor's assets rather than an entire treasury. It is not a true sandbox, however—the owner can call anything and drain everything in that instance.

### 2. Treasury operations and atomic rebalancing

A multisig or operations key could use it to atomically:

- Approve a DEX router and swap tokens.
- Split ERC-20 payouts among several recipients.
- Claim rewards and redeploy them.
- Withdraw from one protocol, swap, and deposit into another.
- Revoke approvals after completing an operation.

The atomic bundle prevents partially completed workflows, such as approval succeeding while the subsequent deposit fails.

For a Safe or Base Account owner, assess whether this extra contract is useful: those wallets already support batching. Base Account exposes atomic wallet batches directly. See [Base atomic batching](https://docs.base.org/base-account/reference/core/capabilities/atomic).

The Executor is most valuable when a separate onchain address and asset boundary are needed, not merely batching.

### 3. AI-agent or trading-bot execution account

Base explicitly supports agent-wallet and autonomous-transaction use cases. See [Base resources for AI agents](https://docs.base.org/get-started/resources-for-ai-agents).

A practical architecture would be:

```text
cold treasury / multisig
          |
     limited funding
          v
strategy Executor <- bot owner
          |
   approved Base protocols
```

Use separate Executors with capped funding for market making, recurring swaps, reward harvesting, or automated position maintenance.

As written, the bot remains all-powerful. For serious autonomous use, add target and function allowlists, daily spending limits, an emergency pause, and owner rotation.

### 4. USDC revenue collector and payout account

The Executor address can be used as a Base USDC payment destination, accumulate receipts, and periodically batch:

- Contractor or creator payouts.
- Treasury splits.
- Protocol deposits.
- Bridging or sweeping to cold storage.

Base Pay offers one-tap USDC payments, while Base subscriptions support recurring USDC charges. See [Base Pay](https://docs.base.org/base-account/guides/accept-payments) and [Base subscriptions](https://docs.base.org/base-account/reference/base-pay/subscriptions-overview).

For simple collection and sweeping, however, the arbitrary-call surface may be unnecessary. A multisig or purpose-built payment splitter would have a smaller security footprint.

### 5. Atomic Base-to-Ethereum withdrawals

The Executor can interact with Base's standard bridge contracts. For ERC-20 assets, a bundle could approve the bridge and initiate the withdrawal atomically. Base's L2 Standard Bridge is at `0x4200000000000000000000000000000000000010`. See [Base bridge contracts](https://docs.base.org/base-chain/network-information/base-contracts).

If ownership is meant to be exercised by an L1 contract through a deposit transaction, account for OP Stack address aliasing. L1 contract callers appear on L2 under an aliased address. See the [Base deposit and aliasing specification](https://docs.base.org/base-chain/specs/protocol/bridging/deposits).

## Important limitations

The largest functional issue is ETH accounting.

In `execute`, the target receives exactly the transaction's fresh `msg.value`. In `bundleExecute`, the sum of call values must equal fresh `msg.value`.

Therefore:

- ETH already held by the Executor cannot be spent through arbitrary calls.
- Stored ETH can only be sent using `withdrawEth`.
- A DeFi call requiring native ETH must be funded again by the owner during that transaction.

Other limitations:

- Ownership cannot be transferred. A lost or compromised owner requires deploying another Executor and migrating whatever assets remain.
- It has no ERC-1271 signature support, account-abstraction validation, paymaster support, nonce system, or signed-intent execution.
- It has no permission model below complete control.
- It cannot safely receive ERC-721 or ERC-1155 tokens through their safe-transfer methods because it lacks receiver callbacks. NFTs sent with plain `transferFrom` could be recovered through `execute`.
- `execute` replaces target revert data with `ExecutionFailed`, making failed integrations harder to debug.
- Bundle events emit all target calldata, increasing log cost.
- Protocol approvals can remain active indefinitely unless explicitly revoked.
- Anyone can send it ETH or tokens, after which the owner controls those assets.

## Recommended changes before deploying meaningful value

In priority order:

1. Change `evm_version` from `osaka` to `cancun`.
2. Add Base-specific deployment scripts that assert chain ID `8453` or `84532`.
3. Add Base-mainnet and Base-Sepolia fork tests.
4. Redesign call-value handling so stored ETH can fund executions.
5. Add two-step ownership transfer or set a Safe as owner.
6. For bots, add target and function allowlists, spending caps, a pause, and narrowly scoped session keys.
7. Add ERC-721/ERC-1155 receiver and rescue support if NFTs are in scope.
8. Bubble target revert data or otherwise improve execution diagnostics.
9. Add deployment verification and a post-deployment owner-control test before funding.

## Suggested first deployment

Start with a token-only strategy Executor on Base Sepolia, owned by a Safe or disposable automation key. Test an atomic `approve -> protocol action -> revoke` workflow before extending the contract for native ETH and autonomous operation.
