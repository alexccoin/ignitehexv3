import { useState } from 'react';
import { toast } from 'sonner';
import { ArrowUpFromLine, Info, Loader2, Lock, LockOpen, Unlock } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { byToken } from '@/lib/balances';
import { shortDate, token as formatToken } from '@/lib/format';
import { LockProgress, Section, apyLabel, lockState } from './components';
import { LOCK_PERIODS, lockPeriodsFor, poolTypeLabel, type LockPeriod, type PoolType, isPoolType } from './constants';
import {
  PAYOUT_ADDRESS_PATTERN,
  PAYOUT_NETWORK,
  useMyPayoutRequests,
  useRequestExternalPayout,
  useStakingPortfolio,
  useSubmitStakingRequest,
  type PoolRow,
} from './hooks';

/**
 * Unstaking.
 *
 * Two things v2 got wrong are fixed here.
 *
 * First, eligibility. v2 computed it in the browser from `created_at` plus a
 * hardcoded map of days per token, which contradicted the `lock_end_date` the
 * rest of the app displayed. Both the lock bar and the control state are now
 * drawn from the position's own `lock_end_date` — the term the server recorded
 * against that row — so the two cannot disagree.
 *
 * This page previously asked `is_withdrawal_available` instead, on the grounds
 * that the server should own the answer. It should, but that function reads
 * `founder_positions`, not `user_staking_pools`: given a pool id it matches no
 * row and returns a confident `false`. Every unstake control on this page was
 * therefore permanently disabled (F-077). Until an
 * `is_staking_withdrawal_available(p_pool_id)` exists, the row's own recorded
 * term is the honest source — and it is only deciding whether a member may
 * *ask*, since neither action here moves a balance.
 *
 * Second, the action. v2's "Withdraw" button ran a comment that said
 * "Here you would implement the actual withdrawal logic" followed by a success
 * toast - it told the member their withdrawal was submitted and did nothing at
 * all. Both actions on this page are now real and both are requests:
 *
 *   - Unstaking goes through the `submit-staking-request` edge function.
 *   - Paying out to an external wallet books a `guardian_withdrawal_requests`
 *     row. RLS forces the caller's own user_id onto it, the member has no
 *     UPDATE or DELETE policy so they cannot approve or retract it, and the
 *     operations console already reads the queue. Nothing is debited by this
 *     page; settlement is an operator's job and the panel says so.
 *
 * `withdrawal_requests` — the table whose name suggests it belongs here — is
 * deliberately not used. It is the founder-position BTC table and its UPDATE
 * policy lets the requesting member set their own row to `approved` while no
 * administrator can read it at all (F-074).
 *
 * Everything a member has asked for is listed back to them below the positions,
 * per asset. Quantities of different tokens are never added together.
 */
export default function StakingWithdrawals() {
  const portfolio = useStakingPortfolio();

  const pools = portfolio.data?.pools ?? [];
  const staked = pools.filter((pool) => Number(pool.staked_amount ?? 0) > 0);

  // Named per token rather than summed: 23,542 CCOS and 500 STR are not
  // "24,042" of anything, and this stack has no price feed that could convert
  // them (see lib/balances.ts).
  const positions = portfolio.data?.positions ?? [];
  const stakedByToken = byToken(positions, 'staked', formatToken);
  const rewardsByToken = byToken(positions, 'rewards', formatToken);
  const unlockedCount = staked.filter((pool) => !lockState(pool).locked).length;

  return (
    <>
      <PageHeader
        title="Withdrawals"
        description="Release a position once its lock has run. Requests are reviewed before anything moves."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Currently staked"
          value={stakedByToken}
          sub="Per token — quantities are not added across tokens"
          loading={portfolio.isLoading}
        />
        <Stat
          label="Unclaimed rewards"
          value={rewardsByToken}
          tone="success"
          loading={portfolio.isLoading}
        />
        <Stat
          label="Unlocked positions"
          value={`${unlockedCount} of ${staked.length}`}
          tone={unlockedCount > 0 ? 'primary' : 'default'}
          sub="From each position's recorded lock_end_date"
          loading={portfolio.isLoading}
        />
      </div>

      <div className="mb-6 flex items-start gap-3 rounded-lg border border-info/20 bg-info/10 p-4 text-sm">
        <Info className="mt-0.5 size-4 shrink-0 text-info" />
        <p className="text-muted-foreground">
          An unstake request is recorded for review. Your balance changes only when an administrator
          approves it — this page never adjusts a balance itself.
        </p>
      </div>

      <Section
        title="Your positions"
        description="Lock progress and the unlock decision both come from each position's own lock_end_date. Every action below is a request an operator reviews."
      >
        {portfolio.isLoading ? (
          <div className="grid gap-4 p-5 md:grid-cols-2">
            <Skeleton className="h-52 w-full" />
            <Skeleton className="h-52 w-full" />
          </div>
        ) : portfolio.isError ? (
          <ErrorState error={portfolio.error} onRetry={() => void portfolio.refetch()} />
        ) : staked.length === 0 ? (
          <EmptyState
            title="Nothing staked"
            description="Positions with a staked balance appear here with their lock period and unstake controls."
            icon={<Unlock className="size-5" />}
          />
        ) : (
          <div className="grid gap-4 p-5 md:grid-cols-2">
            {staked.map((pool) => (
              <PositionCard key={pool.id} pool={pool} />
            ))}
          </div>
        )}
      </Section>

      <div className="mt-6">
        <PayoutRequestsSection />
      </div>
    </>
  );
}

/* ------------------------------------------------------- external payouts */

/**
 * Payout requests the member has raised, and where each one stands.
 *
 * A submit button with no visible result is not finished, so this sits on the
 * same screen as the control that creates the rows.
 *
 * Amounts are rendered per asset and never added together. There is no price
 * feed in this stack that could convert 500 STR and 1,900,000 CCOS into one
 * figure, and pretending otherwise is the cross-token summing bug that appeared
 * in six places in v2.
 */
function PayoutRequestsSection() {
  const payouts = useMyPayoutRequests();
  const rows = payouts.data ?? [];

  return (
    <Section
      title="External payout requests"
      description="Requests to move released tokens off the platform. An operator settles each one by hand."
    >
      {payouts.isLoading ? (
        <div className="p-5">
          <Skeleton className="h-24 w-full" />
        </div>
      ) : payouts.isError ? (
        <div className="p-5">
          <ErrorState
            title="Could not load your payout requests"
            error={payouts.error}
            onRetry={() => void payouts.refetch()}
          />
        </div>
      ) : rows.length === 0 ? (
        <EmptyState
          icon={<ArrowUpFromLine className="size-5" />}
          title="No payout requests"
          description="Requests you raise from an unlocked position appear here with their review status."
        />
      ) : (
        <TableWrap>
          <Table>
            <THead>
              <TR>
                <TH>Requested</TH>
                <TH>Asset</TH>
                <TH className="text-right">Amount</TH>
                <TH>Destination</TH>
                <TH>Status</TH>
              </TR>
            </THead>
            <TBody>
              {rows.map((r) => (
                <TR key={r.id}>
                  <TD className="whitespace-nowrap text-muted-foreground">
                    {shortDate(r.requested_at)}
                  </TD>
                  <TD className="font-medium">{r.asset_symbol}</TD>
                  <TD className="tabular whitespace-nowrap text-right font-medium">
                    {formatToken(Number(r.amount), r.asset_symbol)}
                  </TD>
                  <TD>
                    <p className="max-w-[16rem] truncate font-mono text-xs">
                      {r.destination_address}
                    </p>
                    <p className="text-xs text-muted-foreground">{r.network}</p>
                  </TD>
                  <TD>
                    <StatusBadge status={r.status} />
                    {r.admin_notes && (
                      <p className="mt-1 max-w-[16rem] text-xs text-muted-foreground">
                        {r.admin_notes}
                      </p>
                    )}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </TableWrap>
      )}
    </Section>
  );
}

/**
 * The lock period the edge function should record against an unstake.
 *
 * `submit-staking-request` validates `lock_period` for every request type, so
 * the position's own term is echoed back. Domain pools reject a 3-month term,
 * hence the clamp.
 */
function lockPeriodForPosition(pool: PoolRow): LockPeriod {
  const poolType: PoolType = isPoolType(pool.pool_type) ? pool.pool_type : 'str';
  const allowed = lockPeriodsFor(poolType);
  const months = String(pool.stake_duration_months ?? '');
  const match = LOCK_PERIODS.find((p) => p === months);
  return match && allowed.includes(match) ? match : (allowed[allowed.length - 1] ?? '12');
}

function PositionCard({ pool }: { pool: PoolRow }) {
  const [amount, setAmount] = useState('');
  const [error, setError] = useState<string | undefined>();
  const [payoutOpen, setPayoutOpen] = useState(false);
  const submit = useSubmitStakingRequest();

  const lock = lockState(pool);
  const stakedAmount = Number(pool.staked_amount ?? 0);
  const poolType: PoolType = isPoolType(pool.pool_type) ? pool.pool_type : 'str';
  // Released means the position's own recorded term has run. Not a guess and
  // not a per-token constant — the date on the row.
  const canRequest = !lock.locked;

  function handleUnstake() {
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) {
      setError('Enter an amount greater than zero.');
      return;
    }
    if (value > stakedAmount) {
      setError(`This position holds ${formatToken(stakedAmount, poolType)}.`);
      return;
    }
    setError(undefined);

    submit.mutate(
      {
        poolType,
        requestType: 'unstake',
        amount: value,
        lockPeriod: lockPeriodForPosition(pool),
        description: `Unstake from ${poolTypeLabel(pool.pool_type)} position ${pool.id}`,
        paymentMethod: 'external',
      },
      {
        onSuccess: () => {
          toast.success('Unstake request submitted', {
            description: 'It will be released once an administrator approves it.',
          });
          setAmount('');
        },
        onError: (err: Error) =>
          toast.error('Could not submit the request', { description: err.message }),
      }
    );
  }

  return (
    <article className="flex flex-col gap-4 rounded-lg border border-border p-4">
      <header className="flex items-start justify-between gap-3">
        <div>
          <h3 className="flex items-center gap-2 font-semibold">
            {poolTypeLabel(pool.pool_type)}
            {pool.is_enhanced_pool && <Badge tone="info">Enhanced</Badge>}
          </h3>
          <p className="tabular mt-1 text-lg font-semibold">
            {formatToken(stakedAmount, poolType)}
          </p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {apyLabel(pool)} APY · {formatToken(Number(pool.rewards_earned ?? 0), poolType)} earned
          </p>
        </div>
        {canRequest ? (
          <Badge tone="success">
            <LockOpen className="size-3" />
            Unlocked
          </Badge>
        ) : (
          <Badge tone="warning">
            <Lock className="size-3" />
            Locked
          </Badge>
        )}
      </header>

      <LockProgress state={lock} />

      <div className="space-y-3 border-t border-border pt-3">
        <Field
          label="Amount to unstake"
          htmlFor={`unstake-${pool.id}`}
          error={error}
          hint={canRequest ? undefined : `Available once the lock runs — ${lock.label}.`}
        >
          <Input
            id={`unstake-${pool.id}`}
            type="number"
            inputMode="decimal"
            min="0"
            step="any"
            max={stakedAmount}
            value={amount}
            disabled={!canRequest || submit.isPending}
            aria-invalid={!!error}
            onChange={(event) => setAmount(event.target.value)}
            placeholder="0.00"
          />
        </Field>

        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            size="sm"
            disabled={!canRequest || submit.isPending}
            onClick={handleUnstake}
          >
            {submit.isPending && <Loader2 className="animate-spin" />}
            Request unstake
          </Button>

          {/*
            Requesting an external payout is a client write because it moves
            nothing: it books a `guardian_withdrawal_requests` row that RLS
            forces to carry the caller's own user_id, that the member cannot
            approve, complete or delete, and that the operations console already
            reviews. v2's version of this button was wired straight to a success
            toast and did nothing at all.

            TODO(server): settlement still needs a routine — something along the
            lines of `process-staking-withdrawal` that verifies the caller holds
            the role, re-checks the position is released, debits it, broadcasts
            and records the hash in one transaction. Nothing is debited until
            that runs, and the panel below says so.
          */}
          <Button
            type="button"
            size="sm"
            variant="secondary"
            disabled={!canRequest}
            onClick={() => setPayoutOpen((open) => !open)}
            aria-expanded={payoutOpen}
            title={
              canRequest
                ? undefined
                : `Available once the lock runs — ${lock.label}.`
            }
          >
            <ArrowUpFromLine />
            {payoutOpen ? 'Close payout form' : 'Request payout to external wallet'}
          </Button>
        </div>

        {payoutOpen && canRequest && (
          <PayoutRequestForm
            assetSymbol={poolType.toUpperCase()}
            releasedAmount={stakedAmount}
            poolType={poolType}
            onDone={() => setPayoutOpen(false)}
          />
        )}
      </div>
    </article>
  );
}

/**
 * Ask for a released position to be paid out to an external wallet.
 *
 * One asset per request. The amount is capped at what this position holds so a
 * member is not invited to type a figure that cannot be met — but that cap is a
 * courtesy, not the control. There is no database-side check that the amount is
 * covered (confirmed: an INSERT for 999 units against a zero balance succeeds),
 * so the panel says in plain words that an operator verifies the figure and
 * that nothing moves until they do, rather than implying the number was
 * enforced.
 */
function PayoutRequestForm({
  assetSymbol,
  releasedAmount,
  poolType,
  onDone,
}: {
  assetSymbol: string;
  releasedAmount: number;
  poolType: PoolType;
  onDone: () => void;
}) {
  const [amount, setAmount] = useState('');
  const [destination, setDestination] = useState('');
  const request = useRequestExternalPayout();

  const value = Number(amount);
  const amountError =
    amount && (!Number.isFinite(value) || value <= 0)
      ? 'Enter an amount greater than zero.'
      : amount && value > releasedAmount
        ? `This position holds ${formatToken(releasedAmount, poolType)}.`
        : undefined;

  const destinationError =
    destination && !PAYOUT_ADDRESS_PATTERN.test(destination.trim())
      ? 'Expected a str_ address or an 0x address.'
      : undefined;

  const canSubmit =
    !!amount && !!destination.trim() && !amountError && !destinationError && !request.isPending;

  function submit() {
    if (!canSubmit) return;
    request.mutate(
      { assetSymbol, amount: value, destinationAddress: destination.trim() },
      {
        onSuccess: () => {
          toast.success('Payout request submitted', {
            description: `${formatToken(value, poolType)} is queued for review. Nothing has moved yet.`,
          });
          setAmount('');
          setDestination('');
          onDone();
        },
        onError: (err: Error) =>
          toast.error('Could not submit the payout request', { description: err.message }),
      }
    );
  }

  return (
    <div className="space-y-3 rounded-lg border border-border bg-elevated p-3">
      <p className="text-xs text-muted-foreground">
        This raises a request on the {PAYOUT_NETWORK} network for an operator to settle by hand. The
        amount you enter is not checked against your balance by the database — the operator verifies
        it, and your position is not debited until they do.
      </p>

      <Field
        label={`Amount to pay out (${assetSymbol})`}
        htmlFor={`payout-amount-${assetSymbol}-${releasedAmount}`}
        error={amountError}
        hint={`Held in this position: ${formatToken(releasedAmount, poolType)}`}
      >
        <Input
          id={`payout-amount-${assetSymbol}-${releasedAmount}`}
          type="number"
          inputMode="decimal"
          min="0"
          step="any"
          max={releasedAmount}
          value={amount}
          disabled={request.isPending}
          aria-invalid={!!amountError}
          onChange={(event) => setAmount(event.target.value)}
          placeholder="0.00"
        />
      </Field>

      <Field
        label="Destination wallet"
        htmlFor={`payout-address-${assetSymbol}-${releasedAmount}`}
        error={destinationError}
        hint="Where the tokens should be sent. Check it — an operator cannot recall a settled payout."
      >
        <Input
          id={`payout-address-${assetSymbol}-${releasedAmount}`}
          value={destination}
          disabled={request.isPending}
          spellCheck={false}
          aria-invalid={!!destinationError}
          onChange={(event) => setDestination(event.target.value)}
          placeholder="str_… or 0x…"
          className="font-mono text-xs"
        />
      </Field>

      <Button type="button" size="sm" disabled={!canSubmit} onClick={submit}>
        {request.isPending && <Loader2 className="animate-spin" />}
        Send payout request
      </Button>
    </div>
  );
}
