import { useState } from 'react';
import { ClipboardList, History, Sparkles } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { StatusBadge } from '@/components/ui/status';
import { Badge } from '@/components/ui/badge';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { Stat } from '@/components/ui/stat';
import { byToken, byUnit } from '@/lib/balances';
import { relativeTime, shortDate, token as formatToken } from '@/lib/format';
import { Section, Segmented, apyLabel, lockState } from './components';
import { poolTypeLabel } from './constants';
import { useMyStakingRequests, useRewardActivity, useStakingPortfolio } from './hooks';

/**
 * Everything that has happened to this member's stake.
 *
 * v2's equivalent screen had a "Requests History" tab wired to a hardcoded
 * empty array with a comment saying the table did not exist yet. It does, so it
 * is read here: a request the member submitted and an administrator declined
 * was previously invisible to them.
 */

const RANGES = [
  { value: '7', label: '7 days' },
  { value: '30', label: '30 days' },
  { value: '90', label: '90 days' },
  { value: '365', label: '12 months' },
] as const;

type Range = (typeof RANGES)[number]['value'];

export default function StakingHistory() {
  const [range, setRange] = useState<Range>('30');

  const requests = useMyStakingRequests();
  const activity = useRewardActivity(Number(range));
  const portfolio = useStakingPortfolio();

  const requestRows = requests.data ?? [];
  const activityRows = activity.data ?? [];
  const pools = portfolio.data?.pools ?? [];
  const positions = portfolio.data?.positions ?? [];

  /**
   * Both figures used to be one cross-unit sum labelled with a single symbol:
   * every credit added up and called wSTR, every pool's rewards added up and
   * called STR. `arss_transactions` carries its own `currency` per row and the
   * pools carry their own `pool_type`, so each is named in the unit it is
   * actually denominated in.
   */
  const creditedInRange = byUnit(
    activityRows.map((row) => ({ unit: row.currency ?? 'unknown', amount: Number(row.amount ?? 0) })),
    formatToken
  );
  const lifetimeRewards = byToken(positions, 'rewards', formatToken);

  return (
    <>
      <PageHeader
        title="Staking history"
        description="Requests you have submitted, rewards credited to you and the positions you hold."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Requests submitted"
          value={requestRows.length}
          icon={<ClipboardList className="size-4" />}
          loading={requests.isLoading}
        />
        <Stat
          label={`Credited in ${RANGES.find((r) => r.value === range)?.label ?? ''}`}
          value={creditedInRange}
          tone="success"
          loading={activity.isLoading}
        />
        <Stat
          label="Lifetime rewards on positions"
          value={lifetimeRewards}
          tone="primary"
          loading={portfolio.isLoading}
        />
      </div>

      <div className="space-y-6">
        <Section
          title="Requests"
          description="Every stake and unstake you have asked for, with the reviewer's decision."
        >
          {requests.isLoading ? (
            <TableSkeleton />
          ) : requests.isError ? (
            <ErrorState error={requests.error} onRetry={() => void requests.refetch()} />
          ) : requestRows.length === 0 ? (
            <EmptyState
              title="No requests yet"
              description="Stake and unstake requests appear here as soon as you submit them."
              icon={<ClipboardList className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Submitted</TH>
                    <TH>Type</TH>
                    <TH>Token</TH>
                    <TH className="text-right">Amount</TH>
                    <TH>Term</TH>
                    <TH>Status</TH>
                    <TH>Reviewed</TH>
                    <TH>Notes</TH>
                  </TR>
                </THead>
                <TBody>
                  {requestRows.map((row) => (
                    <TR key={row.id}>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(row.requested_at ?? row.created_at)}
                      </TD>
                      <TD>
                        <Badge tone={row.request_type === 'unstake' ? 'warning' : 'primary'}>
                          {row.request_type === 'unstake' ? 'Unstake' : 'Stake'}
                        </Badge>
                      </TD>
                      <TD className="font-medium">{poolTypeLabel(row.pool_type)}</TD>
                      <TD className="tabular text-right">
                        {formatToken(Number(row.amount ?? 0), row.pool_type)}
                      </TD>
                      <TD className="tabular">{row.duration_months} mo</TD>
                      <TD>
                        <StatusBadge status={row.status} />
                      </TD>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {row.processed_at ? relativeTime(row.processed_at) : '—'}
                      </TD>
                      <TD className="max-w-xs text-muted-foreground">
                        {row.admin_notes || row.domain_name || '—'}
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>

        <Section
          title="Reward activity"
          description="Credits booked to your account by the distribution routines."
          actions={
            <Segmented
              label="Reward activity period"
              options={RANGES}
              value={range}
              onChange={setRange}
            />
          }
        >
          {activity.isLoading ? (
            <TableSkeleton />
          ) : activity.isError ? (
            <ErrorState error={activity.error} onRetry={() => void activity.refetch()} />
          ) : activityRows.length === 0 ? (
            <EmptyState
              title="Nothing credited in this period"
              description="Rewards accrue once a position has been open for a full day."
              icon={<Sparkles className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Date</TH>
                    <TH>Type</TH>
                    <TH className="text-right">Amount</TH>
                    <TH>Status</TH>
                    <TH>Description</TH>
                  </TR>
                </THead>
                <TBody>
                  {activityRows.map((row) => (
                    <TR key={row.id}>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(row.created_at)}
                      </TD>
                      <TD className="capitalize">{row.transaction_type.replace(/_/g, ' ')}</TD>
                      <TD className="tabular text-right text-success">
                        {formatToken(Number(row.amount ?? 0), row.currency ?? 'wstr')}
                      </TD>
                      <TD>
                        <StatusBadge status={row.status} />
                      </TD>
                      <TD className="max-w-md text-muted-foreground">{row.description || '—'}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>

        <Section
          title="Positions opened"
          description="Each position, when it opened and how far through its lock it is."
        >
          {portfolio.isLoading ? (
            <TableSkeleton />
          ) : portfolio.isError ? (
            <ErrorState error={portfolio.error} onRetry={() => void portfolio.refetch()} />
          ) : pools.length === 0 ? (
            <EmptyState
              title="No positions opened"
              description="Approved stake requests become positions and are listed here."
              icon={<History className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Opened</TH>
                    <TH>Token</TH>
                    <TH className="text-right">Staked</TH>
                    <TH className="text-right">Rewards</TH>
                    <TH className="text-right">APY</TH>
                    <TH>Lock ends</TH>
                    <TH>Last reward</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {pools.map((pool) => {
                    const lock = lockState(pool);
                    return (
                      <TR key={pool.id}>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {shortDate(pool.created_at)}
                        </TD>
                        <TD className="font-medium">{poolTypeLabel(pool.pool_type)}</TD>
                        <TD className="tabular text-right">
                          {formatToken(Number(pool.staked_amount ?? 0), pool.pool_type)}
                        </TD>
                        <TD className="tabular text-right text-success">
                          {formatToken(Number(pool.rewards_earned ?? 0), pool.pool_type)}
                        </TD>
                        <TD className="tabular text-right">{apyLabel(pool)}</TD>
                        <TD className="whitespace-nowrap">
                          <span className={lock.locked ? 'text-warning' : 'text-muted-foreground'}>
                            {lock.endsAt ? shortDate(lock.endsAt) : '—'}
                          </span>
                        </TD>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {pool.last_reward_date ? shortDate(pool.last_reward_date) : 'Never'}
                        </TD>
                        <TD>
                          <StatusBadge status={pool.status} />
                        </TD>
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>
      </div>
    </>
  );
}

function TableSkeleton() {
  return (
    <div className="space-y-3 p-5">
      <Skeleton className="h-9 w-full" />
      <Skeleton className="h-9 w-full" />
      <Skeleton className="h-9 w-full" />
    </div>
  );
}
