import { useState } from 'react';
import { toast } from 'sonner';
import { ArrowUpFromLine, Info, Loader2, Lock, LockOpen, Unlock } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { byToken } from '@/lib/balances';
import { token as formatToken } from '@/lib/format';
import { LockProgress, Section, apyLabel, lockState } from './components';
import { LOCK_PERIODS, lockPeriodsFor, poolTypeLabel, type LockPeriod, type PoolType, isPoolType } from './constants';
import { useStakingPortfolio, useSubmitStakingRequest, useWithdrawalAvailability, type PoolRow } from './hooks';

/**
 * Unstaking.
 *
 * Two things v2 got wrong are fixed here.
 *
 * First, eligibility. v2 computed it in the browser from `created_at` plus a
 * hardcoded map of days per token, which contradicted the `lock_end_date` the
 * rest of the app displayed. Here the lock bar is drawn from `lock_end_date`
 * and the actual permission comes from the `is_withdrawal_available` function
 * in the database, so the button state matches what the server will allow.
 *
 * Second, the action. v2's "Withdraw" button ran a comment that said
 * "Here you would implement the actual withdrawal logic" followed by a success
 * toast - it told the member their withdrawal was submitted and did nothing at
 * all. Requesting an unstake goes through the `submit-staking-request` edge
 * function, which is real; moving tokens to an external wallet has no
 * server-side implementation, so that button is disabled rather than faked.
 */
export default function StakingWithdrawals() {
  const portfolio = useStakingPortfolio();

  const pools = portfolio.data?.pools ?? [];
  const staked = pools.filter((pool) => Number(pool.staked_amount ?? 0) > 0);
  const availability = useWithdrawalAvailability(staked.map((pool) => pool.id));

  // Named per token rather than summed: 23,542 CCOS and 500 STR are not
  // "24,042" of anything, and this stack has no price feed that could convert
  // them (see lib/balances.ts).
  const positions = portfolio.data?.positions ?? [];
  const stakedByToken = byToken(positions, 'staked', formatToken);
  const rewardsByToken = byToken(positions, 'rewards', formatToken);
  const unlockedCount = staked.filter((pool) => availability.data?.[pool.id] === true).length;

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
          value={availability.isLoading ? '—' : `${unlockedCount} of ${staked.length}`}
          tone={unlockedCount > 0 ? 'primary' : 'default'}
          sub="Confirmed by the server"
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
        description="Lock progress comes from each position's lock_end_date; the unlock decision comes from the database."
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
              <PositionCard
                key={pool.id}
                pool={pool}
                unlocked={availability.data?.[pool.id] ?? null}
                availabilityFailed={availability.isError}
              />
            ))}
          </div>
        )}
      </Section>
    </>
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

function PositionCard({
  pool,
  unlocked,
  availabilityFailed,
}: {
  pool: PoolRow;
  /** Null while the server has not answered. Never guessed in the browser. */
  unlocked: boolean | null;
  availabilityFailed: boolean;
}) {
  const [amount, setAmount] = useState('');
  const [error, setError] = useState<string | undefined>();
  const submit = useSubmitStakingRequest();

  const lock = lockState(pool);
  const stakedAmount = Number(pool.staked_amount ?? 0);
  const poolType: PoolType = isPoolType(pool.pool_type) ? pool.pool_type : 'str';
  const canRequest = unlocked === true;

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
        {unlocked === null ? (
          <Badge tone="neutral">
            {availabilityFailed ? 'Status unavailable' : 'Checking…'}
          </Badge>
        ) : unlocked ? (
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
          hint={canRequest ? undefined : 'Available once the server reports this position unlocked.'}
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
            TODO(server): moving released tokens to an external wallet needs a
            server-side routine — an edge function along the lines of
            `process-staking-withdrawal` that verifies the caller, checks the
            position is released, debits it and records the payout in one
            transaction. There is no such function today, and a client must
            never perform that debit itself, so the control stays disabled.
            v2 shipped this button wired to a success toast and nothing else.
          */}
          <Button
            type="button"
            size="sm"
            variant="secondary"
            disabled
            title="Not available yet — external payouts need a server-side routine."
          >
            <ArrowUpFromLine />
            Withdraw to external wallet
          </Button>
        </div>
      </div>
    </article>
  );
}
