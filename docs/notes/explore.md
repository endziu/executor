# Reasonable uses for the Executor

The Executor is a single-owner execution account. It holds ETH and ERC-20
balances, spends stored ETH on payable calls (call `value` is independent of
`msg.value`), batches calls atomically via `bundleExecute`, and retains anything
it doesn't spend. The list below is what that reasonably enables on Base.

## Uses

- **Pre-funded payable actions** — Keep a bounded ETH reserve and make payable
  protocol calls (mints, auction bids, collateral deposits, router calls, fees,
  factory calls) without attaching exact ETH to every transaction. The owner
  still pays outer gas; the reserve funds the call. Strongest new capability.

- **ETH → WETH → protocol bundles** — Wrap stored ETH via WETH9
  (`0x4200…0006`), approve, then deposit/swap, and optionally revoke the
  approval — all atomic in one bundle. Makes native ETH usable in ERC-20-only
  protocols without an external wrap step.

- **Mixed ETH + token rebalancing** — Coordinate native ETH and ERC-20 legs in
  one atomic bundle: wrap-and-enter a position, spend ETH through a payable
  router and deposit the output token, or exit a position, swap to ETH, and keep
  the ETH as working capital. Tokens received by an earlier leg are usable by
  later legs.

- **Atomic ETH distributions** — Empty-calldata calls send stored ETH to EOAs,
  so a bundle can do all-or-nothing payouts: payroll/grants, treasury or revenue
  splits, refund batches, operational sweeps. A single rejecting recipient
  reverts the whole bundle — not a fit when one failure shouldn't block the rest.

- **Revenue / refund recycling** — `receive()` accepts ETH from anyone and
  payable targets can refund ETH mid-execution. Accumulated refunds, fees, and
  residual ETH stay in the balance and fund the next owner transaction directly —
  no withdraw-and-refund round trip. One fungible pool, no per-depositor
  accounting.

- **Base → Ethereum ETH withdrawals** — Initiate a native bridge withdrawal
  straight from stored ETH via the L2 Standard Bridge (`0x4200…0010`,
  `bridgeETH`/`bridgeETHTo`) instead of withdrawing to the owner first. Async:
  still proven and finalized on L1; choose the L1 recipient deliberately.

- **Reusable settlement balance for automation** — A keeper can read the
  balance, simulate a bundle, and submit a transaction that spends only what's
  requested, leaving the rest for the next job. Removes just-in-time funding per
  task. Not trustless: a compromised automation owner loses the whole balance —
  one narrowly funded Executor per strategy, Safe or policy contract as owner.

## What it is not

- **Not account abstraction.** It can't pay its own outer-transaction gas; no
  relayer, paymaster, or signed-intent interface.
- **No mid-bundle ETH reuse.** The sum of all outgoing `values` must fit the
  entry balance, even if an earlier leg unwraps WETH or receives a refund. That
  ETH is spendable in a *later* transaction, not the same bundle.
- **No callbacks.** Flash loans, swap callbacks, and named-receiver hooks aren't
  supported by arbitrary outbound calls; the reentrancy guard also blocks
  re-entry into `execute`/`bundleExecute`.
- **No direct contract creation.** It can call a factory but exposes no
  `CREATE`/`CREATE2`.
- **Not a multi-user vault.** Deposits aren't attributed and create no claim.
- **Not NFT-safe.** No ERC-721/1155 receiver callbacks, so safe transfers to it
  fail.
