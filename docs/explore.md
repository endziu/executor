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

## Potential future upgrades

Each of these is a deliberate design boundary today, not an accident — but each
is also a natural direction a future Executor could grow toward. They're listed
roughly easiest-to-hardest to add.

- **NFT-safe receiver hooks.** Implement `onERC721Received` /
  `onERC1155Received` (and `supportsInterface`) so safe transfers land instead
  of reverting. Low-risk, self-contained, and opens NFT mints, marketplace
  fills, and collateral flows to the same stored-ETH model. Strongest
  near-term candidate.

- **Running balance accounting in bundles.** Track a live balance across legs so
  ETH unwrapped from WETH or refunded by an earlier call becomes spendable by a
  *later* leg in the same bundle, instead of requiring the summed `values` to
  fit the entry balance. Turns wrap→swap→exit sequences into single atomic
  transactions.

- **Contract creation.** Expose a guarded `CREATE` / `CREATE2` path so the
  Executor can deploy from stored ETH — deterministic addresses for counterfactual
  deployments, factories driven by the same reserve. Wider blast radius, so
  gate it carefully.

- **Callback / hook support.** Relax the strict reentrancy posture enough to
  participate in flash loans, swap callbacks, and named-receiver hooks — a
  scoped allowance (e.g. an expected callback target set for the duration of one
  call) rather than a blanket open door. The most security-sensitive change
  here; needs its own threat model.

- **Account abstraction.** Add an ERC-4337 entry-point interface or a
  signed-intent path so the Executor can pay its own outer gas via a paymaster
  and be driven by relayers, not only a funded owner EOA. Largest surface-area
  change; effectively a new contract class.

## Other directions worth considering

Beyond relaxing the current boundaries, these add new machinery rather than
lift an existing restriction:

- **ERC-1271 signature validation.** Implement `isValidSignature` so the
  Executor itself can act as a signer — approving off-chain orders (Permit2,
  CoW, Seaport), joining multisig schemes, or authenticating to protocols that
  gate on a contract signature. Small addition, broad reach.

- **Two-step / recoverable ownership.** Ownership is immutable today, so a
  compromised key means redeploy-and-migrate. A guarded `transferOwnership`
  (two-step accept) or a guardian-based social-recovery path would allow key
  rotation without moving assets. Trades some of the immutability guarantee for
  operational safety — an explicit choice, not a free win.

- **Timelocked / scheduled execution.** Queue a call now and let it become
  executable after a delay (or within a window), giving observers time to react
  and enabling deferred/recurring actions. Pairs naturally with allowlists and
  recovery.

- **Partial-success bundles.** An opt-in bundle mode that tolerates individual
  leg failures (try/catch per call) instead of reverting the whole batch — the
  complement to today's all-or-nothing semantics, for payout batches where one
  rejecting recipient shouldn't block the rest.

- **On-chain simulation view.** A `view`/`staticcall`-based dry-run entry point
  so keepers and frontends can preview a bundle's outcome and balance delta
  without submitting, tightening the automation loop.
