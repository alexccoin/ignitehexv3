import type { ReactNode } from 'react';
import { Coins, Globe, TrendingUp, Wallet } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { Badge } from '@/components/ui/badge';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { byToken } from '@/lib/balances';
import { compact, percent, token as formatToken } from '@/lib/format';
import { StakeRequestForm } from './StakeRequestForm';
import { LockProgress, Section, apyLabel, lockState, poolApy } from './components';
import { poolTypeLabel } from './constants';
import { useAggregateStakingStats, useMyStakingRequests, useStakingPortfolio } from './hooks';

/**
 * The member's staking positions.
 *
 * Staked, liquid and rewards are shown as three separate figures because they
 * are three separate columns. v2's dashboard read `staked_amount || balance`,
 * so any pool with nothing staked reported its liquid holding as staked - the
 * fold in `positionsFromPools` is the only thing that adds these up here.
 */
export default function StakingPositions() {
  const portfolio = useStakingPortfolio();
  const requests = useMyStakingRequests();
  const stats = useAggregateStakingStats();

  const pools = portfolio.data?.pools ?? [];
  const positions = portfolio.data?.positions ?? [];

  /**
   * These three tiles used to read `formatToken(sum of every position, 'str')`.
   * The admin account holds 23,542 CCOS and 500 STR, so the tile said
   * "24,042 STR" - a quantity of nothing, sitting directly above a table that
   * listed the two positions correctly. There is no honest conversion to a
   * common unit here (see lib/balances.ts), so each token is named.
   */
  const stakedByToken = byToken(positions, 'staked', formatToken);
  const liquidByToken = byToken(positions, 'liquid', formatToken);
  const rewardsByToken = byToken(positions, 'rewards', formatToken);

  // Weighted by stake so one large position is not averaged away by a dust one.
  // Cross-token quantities are a legitimate *weight* - the result is a rate, not
  // an amount - so this sum is never rendered.
  const stakeWeight = positions.reduce((sum, p) => sum + p.staked, 0);
  const weightedApy =
    stakeWeight > 0
      ? pools.reduce((sum, pool) => sum + poolApy(pool) * Number(pool.staked_amount ?? 0), 0) /
        stakeWeight
      : 0;

  const pending = (requests.data ?? []).filter((r) => r.status === 'pending');

  return (
    <>
      <PageHeader
        title="Staking"
        description="Your open positions, the rate each one earns and the requests still under review."
        actions={
          pending.length > 0 ? (
            <Badge tone="warning">
              {pending.length} request{pending.length === 1 ? '' : 's'} awaiting review
            </Badge>
          ) : undefined
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Staked"
          value={stakedByToken}
          sub="Per token — quantities are not added across tokens"
          icon={<Coins className="size-4" />}
          loading={portfolio.isLoading}
        />
        <Stat
          label="Liquid"
          value={liquidByToken}
          sub="Held in pools but not locked"
          icon={<Wallet className="size-4" />}
          loading={portfolio.isLoading}
        />
        <Stat
          label="Rewards earned"
          value={rewardsByToken}
          tone="success"
          loading={portfolio.isLoading}
        />
        <Stat
          label="Weighted APY"
          value={percent(weightedApy)}
          tone="primary"
          sub="From each position's stored rate"
          icon={<TrendingUp className="size-4" />}
          loading={portfolio.isLoading}
        />
      </div>

      <div className="space-y-6">
        <Section
          title="Positions"
          description="Staked and liquid are separate columns — they are separate balances."
        >
          {portfolio.isLoading ? (
            <div className="space-y-3 p-5">
              <Skeleton className="h-9 w-full" />
              <Skeleton className="h-9 w-full" />
              <Skeleton className="h-9 w-full" />
            </div>
          ) : portfolio.isError ? (
            <ErrorState error={portfolio.error} onRetry={() => void portfolio.refetch()} />
          ) : pools.length === 0 ? (
            <EmptyState
              title="No staking positions yet"
              description="Submit a stake request below. Once an administrator approves it, the position appears here with the rate the database assigned."
              icon={<Coins className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Token</TH>
                    <TH className="text-right">Staked</TH>
                    <TH className="text-right">Liquid</TH>
                    <TH className="text-right">Rewards</TH>
                    <TH className="text-right">APY</TH>
                    <TH>Term</TH>
                    <TH className="min-w-44">Lock</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {pools.map((pool) => (
                    <TR key={pool.id}>
                      <TD className="font-medium">
                        <span className="flex items-center gap-2">
                          {poolTypeLabel(pool.pool_type)}
                          {pool.is_enhanced_pool && <Badge tone="info">Enhanced</Badge>}
                        </span>
                      </TD>
                      <TD className="tabular text-right">
                        {formatToken(Number(pool.staked_amount ?? 0), pool.pool_type)}
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {formatToken(Number(pool.balance ?? 0), pool.pool_type)}
                      </TD>
                      <TD className="tabular text-right text-success">
                        {formatToken(Number(pool.rewards_earned ?? 0), pool.pool_type)}
                      </TD>
                      <TD className="tabular text-right">{apyLabel(pool)}</TD>
                      <TD className="tabular">
                        {pool.stake_duration_months ? `${pool.stake_duration_months} mo` : '—'}
                      </TD>
                      <TD>
                        <LockProgress state={lockState(pool)} />
                      </TD>
                      <TD>
                        <StatusBadge status={pool.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>

        <Section
          title="Open a position"
          description="Submitted for review — no balance moves until an administrator approves it."
        >
          <StakeRequestForm positions={positions} />
        </Section>

        <Section
          title="Across the network"
          description="Totals computed by the database, not by summing every row in the browser."
        >
          {stats.isLoading ? (
            <div className="grid gap-4 p-5 sm:grid-cols-3">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
          ) : stats.isError ? (
            <ErrorState error={stats.error} onRetry={() => void stats.refetch()} />
          ) : !stats.data ? (
            <EmptyState title="No network figures available" />
          ) : (
            <div className="grid gap-4 p-5 sm:grid-cols-3">
              <NetworkFigure
                label="STR staked"
                amount={stats.data.total_str_staked}
                stakers={stats.data.total_str_stakers}
                apy={stats.data.avg_str_apy}
              />
              <NetworkFigure
                label="CCOS staked"
                amount={stats.data.total_ccos_staked}
                stakers={stats.data.total_ccos_stakers}
                apy={stats.data.avg_ccos_apy}
              />
              <NetworkFigure
                label="Domains staked"
                amount={stats.data.total_domain_staked}
                stakers={stats.data.total_domain_stakers}
                apy={stats.data.avg_domain_apy}
                icon={<Globe className="size-4" />}
              />
            </div>
          )}
        </Section>
      </div>
    </>
  );
}

function NetworkFigure({
  label,
  amount,
  stakers,
  apy,
  icon,
}: {
  label: string;
  amount: number | null;
  stakers: number | null;
  apy: number | null;
  icon?: ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border p-4">
      <p className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {icon}
        {label}
      </p>
      <p className="tabular mt-2 text-xl font-semibold">{compact(amount)}</p>
      <p className="mt-1 text-xs text-muted-foreground">
        {compact(stakers)} stakers · {percent(apy)} average
      </p>
    </div>
  );
}
