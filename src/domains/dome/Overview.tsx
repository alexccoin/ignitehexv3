import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  ArrowUpRight,
  BadgeCheck,
  Calculator,
  Coins,
  Gauge,
  Layers,
  Scale,
  Sparkles,
  TrendingUp,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { byToken } from '@/lib/balances';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TrendChart } from '@/components/ui/charts';
import { useStakingPools, useTransactions, useV2Account } from '@/hooks/data';
import { token } from '@/lib/format';
import { useAuth } from '@/features/auth/AuthProvider';
import {
  ActivityFeed,
  ComparisonBar,
  MetricRow,
  MilestoneTrack,
  NoticesPanel,
  RoundTermsModal,
  SUPPLY_NOTE,
  count,
  ownershipPct,
  usd,
  type ActivityEntry,
  type Milestone,
} from './components';
import { TOTAL_SUPPLY, useDomeEquity } from './hooks';

/**
 * The Dome overview.
 *
 * This is the prototype's `OverviewSections` + `EarningsColumn` composition:
 * a round banner, a welcome panel beside a progress track, a row of headline
 * tiles, then a two-column body with the allocation history and activity on the
 * left and the earnings column pinned to the right.
 *
 * What changed is where the numbers come from. In the prototype the welcome
 * panel greeted "Alex S." at `str.ilieslj1`, the tiles read 31,250 shares /
 * $1.60 / $3.00 / $93,750, and the estimator's "Your Ownership" was the string
 * `0.094%` — every one of them a literal, identical for every visitor. Here the
 * name comes from the member's V2 account, the tiles from their own allocation
 * records, and the estimator's ownership from their own share count.
 *
 * Deliberately absent, because the schema has nothing behind them:
 *  - the named tier ladder (Origin → Signal → Ascend → Apex) and its "Top 0.1%"
 *    chip: no tier column, no threshold table;
 *  - the "Round ends in 14d 22h 33m 12s" countdown and the "Starting Jan 2027"
 *    dividend date: no round or distribution calendar;
 *  - the "Upgrade to Genesis Crown / 62,500 shares / +100% More Shares" card:
 *    no package catalogue. The upgrade panel instead links to the investments
 *    domain, which is a route that exists.
 */

const REVENUE_PRESETS = [10, 50, 100];

export default function DomeOverview() {
  const { user } = useAuth();
  const equity = useDomeEquity();
  const v2 = useV2Account();
  const pools = useStakingPools();
  const txns = useTransactions(6);

  const [termsOpen, setTermsOpen] = useState(false);

  // Estimator inputs. These are the member's assumptions, not data — the panel
  // says so, and the only figure it takes from the database is the share count.
  const [revenue, setRevenue] = useState(50);
  const [growth, setGrowth] = useState(1.2);
  const [margin, setMargin] = useState(30);
  const [simulatedShares, setSimulatedShares] = useState<number | null>(null);

  const m = equity.metrics;
  const account = v2.data?.account ?? null;
  const positions = pools.data?.positions ?? [];
  // Not summed: rewards accrue in the pool's own token, and "626.46 wSTR" was
  // the CCOS and STR figures added together under a third token's name.
  const rewardsByToken = byToken(positions, 'rewards', token);

  const displayName =
    account?.full_name ??
    (user?.user_metadata?.full_name as string | undefined) ??
    user?.email ??
    'Member';

  const milestones: Milestone[] = useMemo(
    () =>
      m.counted.map((record) => ({
        id: record.id,
        title: record.programme,
        detail: `${count(record.shares + record.bonusShares)} shares${
          record.pricePerShare > 0 ? ` @ ${usd(record.pricePerShare, 3)}` : ''
        }`,
        date: record.date,
      })),
    [m.counted]
  );

  const activity: ActivityEntry[] = useMemo(() => {
    const fromAllocations = m.records.slice(0, 3).map((record) => ({
      id: record.id,
      title: `${record.programme} · ${count(record.shares + record.bonusShares)} shares`,
      detail: `${record.invested > 0 ? usd(record.invested) : 'no cost recorded'} · ${record.status}`,
      date: record.date,
    }));

    const fromPools = (pools.data?.pools ?? []).slice(0, 3).map((pool) => ({
      id: `pool-${pool.id}`,
      title: `Staking pool · ${(pool.pool_type ?? 'str').toUpperCase()}`,
      detail: `${token(Number(pool.staked_amount ?? 0), pool.pool_type ?? 'str')} staked`,
      date: pool.created_at ?? '',
    }));

    const fromTxns = (txns.data ?? []).map((tx) => ({
      id: `tx-${tx.id}`,
      title: tx.from_user_id === user?.id ? 'Transfer sent' : 'Transfer received',
      detail: `${token(Number(tx.amount ?? 0), tx.token_type)} · ${tx.status}`,
      date: tx.created_at ?? '',
    }));

    return [...fromAllocations, ...fromPools, ...fromTxns]
      .filter((entry) => !!entry.date)
      .sort((a, b) => +new Date(b.date) - +new Date(a.date))
      .slice(0, 6);
  }, [m.records, pools.data, txns.data, user?.id]);

  // The estimator. `estimatorShares` is the member's real holding unless they
  // have deliberately moved the shares slider, in which case the panel is
  // labelled "simulated" and offers a way back to the real figure.
  const estimatorShares = simulatedShares ?? m.shares;
  const simulating = simulatedShares !== null && simulatedShares !== m.shares;
  const estimatorOwnership = (estimatorShares / TOTAL_SUPPLY) * 100;
  const quarterRevenue = revenue * 1_000_000 * growth;
  const quarterProfit = quarterRevenue * (margin / 100);
  const quarterPayout = quarterProfit * (estimatorOwnership / 100);

  const loading = equity.isLoading;

  return (
    <>
      <PageHeader
        title="Dome"
        description="Your ownership file: what has been allocated to you, what it is worth on record, and what it could pay."
        actions={
          <Button variant="secondary" onClick={() => setTermsOpen(true)}>
            Round terms
          </Button>
        }
      />

      {/* The prototype's round banner. Its copy was fixed at "+87.5% more shares
          vs public buyers"; here the sentence is built from this member's own
          advantage, and says so plainly when there is no priced round to
          compare against. */}
      <Card className="mb-6 border-primary/30 bg-primary/5">
        <CardContent className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-start gap-3">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
              <Sparkles className="size-5" aria-hidden="true" />
            </span>
            <div className="space-y-1">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                {v2.isLoading ? 'Checking your file' : account ? 'Owner file' : 'No owner file yet'}
              </p>
              {loading ? (
                <Skeleton className="h-5 w-72" />
              ) : (
                <p className="font-medium">
                  {m.extraPct !== null
                    ? `You hold ${m.extraPct.toFixed(1)}% more shares than the same money would buy at the latest recorded price.`
                    : m.hasEquity
                      ? 'Your allocations carry no recorded price per share, so no comparison can be drawn.'
                      : 'No equity has been allocated to your file yet.'}
                </p>
              )}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {account && <StatusBadge status={account.status} />}
            <Button variant="ghost" size="sm" onClick={() => setTermsOpen(true)}>
              View terms
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Welcome + progress track. */}
      <div className="mb-6 grid gap-4 lg:grid-cols-3">
        <Card>
          <CardContent className="space-y-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Welcome back
            </p>
            <h2 className="truncate text-xl font-semibold tracking-tight">{displayName}</h2>
            <p className="truncate text-sm text-muted-foreground">
              {account?.str_domain ?? 'No str.name linked to your file'}
            </p>
            <div className="flex flex-wrap items-center gap-2 pt-1">
              {account?.status === 'approved' ? (
                <Badge tone="success">
                  <BadgeCheck className="size-3.5" aria-hidden="true" />
                  Verified owner
                </Badge>
              ) : (
                <Badge tone="neutral">Verification {account?.status ?? 'not started'}</Badge>
              )}
              {account?.account_mode && <Badge tone="neutral">{account.account_mode} mode</Badge>}
            </div>
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="text-base">Allocation track</CardTitle>
              <CardDescription>Each settled allocation on your file, in order.</CardDescription>
            </div>
            <Badge tone="primary">
              {ownershipPct(m.ownership)} {SUPPLY_NOTE}
            </Badge>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-20 w-full" />
            ) : equity.isError ? (
              <ErrorState error={equity.error} onRetry={equity.refetch} />
            ) : (
              <MilestoneTrack milestones={milestones} />
            )}
          </CardContent>
        </Card>
      </div>

      {/* Headline tiles. Every one of these was a literal in the prototype. */}
      <div className="mb-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Shares held"
          value={count(m.shares)}
          sub={`${ownershipPct(m.ownership)} ${SUPPLY_NOTE}`}
          icon={<Layers className="size-4" />}
          loading={loading}
        />
        <Stat
          label="Average paid"
          value={m.avgPrice > 0 ? usd(m.avgPrice, 3) : '—'}
          sub={
            m.counted.length > 0
              ? `Across ${m.counted.length} settled record${m.counted.length === 1 ? '' : 's'}`
              : 'No settled allocations'
          }
          icon={<Scale className="size-4" />}
          loading={loading}
        />
        <Stat
          label="Latest recorded price"
          value={m.hasPricedRound ? usd(m.latestPrice, 3) : '—'}
          sub={
            m.hasPricedRound
              ? 'From your most recent allocation'
              : 'No price per share on record'
          }
          icon={<Gauge className="size-4" />}
          loading={loading}
        />
        <Stat
          label="Indicative value"
          value={m.hasEquity && m.price > 0 ? usd(m.value) : '—'}
          sub={
            m.hasEquity && m.price > 0
              ? `${m.unrealised >= 0 ? '+' : ''}${usd(m.unrealised)} vs invested`
              : 'Needs a recorded price to value'
          }
          tone={m.unrealised > 0 ? 'success' : m.unrealised < 0 ? 'danger' : 'default'}
          icon={<TrendingUp className="size-4" />}
          loading={loading}
        />
      </div>

      {/* Token side of the file, so equity and holdings sit on one screen. */}
      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="$STR liquid"
          value={token(m.strLiquid, 'str')}
          icon={<Coins className="size-4" />}
          loading={loading}
        />
        <Stat label="$STR locked" value={token(m.strLocked, 'str')} loading={loading} />
        <Stat
          label="Staked"
          value={byToken(positions, 'staked', token)}
          sub={`${positions.length} position${positions.length === 1 ? '' : 's'}`}
          loading={pools.isLoading}
        />
        <Stat
          label="Rewards earned"
          value={rewardsByToken}
          sub="Per token — quantities are not added across tokens"
          loading={pools.isLoading}
        />
      </div>

      {/* Body: allocation history and activity on the left, earnings column on
          the right — the prototype's content-grid, in v3's grid utilities. */}
      <div className="grid gap-4 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Allocation history</CardTitle>
                <CardDescription>Cumulative amount invested, oldest first.</CardDescription>
              </div>
              <Badge tone="neutral">
                {m.counted.length} record{m.counted.length === 1 ? '' : 's'}
              </Badge>
            </CardHeader>
            <CardContent>
              {loading ? (
                <Skeleton className="h-48 w-full" />
              ) : equity.isError ? (
                <ErrorState error={equity.error} onRetry={equity.refetch} />
              ) : m.cumulative.length === 0 ? (
                <EmptyState
                  title="No allocations to plot"
                  description="The chart fills in once a settled allocation is recorded against your file."
                />
              ) : (
                <>
                  <TrendChart data={m.cumulative} format={(v) => usd(v)} height={220} />
                  <div className="mt-4 grid gap-3 sm:grid-cols-3">
                    <div>
                      <p className="text-xs text-muted-foreground">Total invested</p>
                      <p className="tabular text-lg font-semibold">{usd(m.invested)}</p>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground">Indicative value</p>
                      <p className="tabular text-lg font-semibold">
                        {m.price > 0 ? usd(m.value) : '—'}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground">Return on record</p>
                      <p className="tabular text-lg font-semibold">
                        {m.roi === null ? '—' : `${m.roi >= 0 ? '+' : ''}${m.roi.toFixed(1)}%`}
                      </p>
                    </div>
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Recent activity</CardTitle>
                <CardDescription>Allocations, staking positions and transfers.</CardDescription>
              </div>
              <Button variant="ghost" size="sm" asChild>
                <Link to="/dome/portfolio">Open portfolio</Link>
              </Button>
            </CardHeader>
            <CardContent className="p-0">
              <ActivityFeed
                entries={activity}
                loading={loading || pools.isLoading || txns.isLoading}
                error={equity.isError ? equity.error : txns.isError ? txns.error : undefined}
                onRetry={() => {
                  equity.refetch();
                  void txns.refetch();
                }}
              />
            </CardContent>
          </Card>
        </div>

        {/* The earnings column. */}
        <aside className="space-y-4">
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Dividend estimator</CardTitle>
                <CardDescription>
                  A projection you drive. Only the share count is read from your file.
                </CardDescription>
              </div>
              <Badge tone={simulating ? 'warning' : 'neutral'}>
                <Calculator className="size-3.5" aria-hidden="true" />
                {simulating ? 'Simulated' : 'Your holding'}
              </Badge>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="rounded-lg bg-elevated p-4">
                <MetricRow label="Quarterly revenue" value={usd(quarterRevenue)} />
                <MetricRow label={`Net margin ${margin}%`} value={usd(quarterProfit)} />
                <MetricRow label="Shares used" value={count(estimatorShares)} />
                <MetricRow
                  label="Your ownership"
                  value={ownershipPct(estimatorOwnership)}
                  hint={SUPPLY_NOTE}
                />
              </div>

              <div className="rounded-lg border border-primary/30 bg-primary/5 p-4">
                <p className="text-xs uppercase tracking-wide text-muted-foreground">
                  Estimated payout
                </p>
                <p className="tabular mt-1 text-2xl font-semibold text-primary">
                  {usd(quarterPayout)}
                </p>
                <p className="text-xs text-muted-foreground">
                  per quarter · {usd(quarterPayout * 4)} per year
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                {REVENUE_PRESETS.map((preset) => (
                  <Button
                    key={preset}
                    size="sm"
                    variant={revenue === preset ? 'primary' : 'outline'}
                    onClick={() => setRevenue(preset)}
                  >
                    ${preset}M/Q
                  </Button>
                ))}
              </div>

              <div className="space-y-3">
                <label className="block space-y-1.5">
                  <span className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Revenue</span>
                    <span className="tabular font-medium">${revenue}M/Q</span>
                  </span>
                  <input
                    type="range"
                    min={10}
                    max={100}
                    step={5}
                    value={revenue}
                    onChange={(e) => setRevenue(Number(e.target.value))}
                    className="w-full accent-primary"
                  />
                </label>
                <label className="block space-y-1.5">
                  <span className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Growth</span>
                    <span className="tabular font-medium">{growth.toFixed(1)}×</span>
                  </span>
                  <input
                    type="range"
                    min={1}
                    max={2}
                    step={0.1}
                    value={growth}
                    onChange={(e) => setGrowth(Number(e.target.value))}
                    className="w-full accent-primary"
                  />
                </label>
                <label className="block space-y-1.5">
                  <span className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Net margin</span>
                    <span className="tabular font-medium">{margin}%</span>
                  </span>
                  <input
                    type="range"
                    min={5}
                    max={60}
                    step={1}
                    value={margin}
                    onChange={(e) => setMargin(Number(e.target.value))}
                    className="w-full accent-primary"
                  />
                </label>
                <label className="block space-y-1.5">
                  <span className="flex items-center justify-between text-sm">
                    <span className="text-muted-foreground">Shares</span>
                    <span className="tabular font-medium">{count(estimatorShares)}</span>
                  </span>
                  <input
                    type="range"
                    min={0}
                    max={Math.max(100_000, m.shares * 2)}
                    step={100}
                    value={estimatorShares}
                    onChange={(e) => setSimulatedShares(Number(e.target.value))}
                    className="w-full accent-primary"
                  />
                </label>
              </div>

              <p className="text-xs text-muted-foreground">
                {m.hasEquity
                  ? 'Revenue, growth and margin are your assumptions. No distribution is scheduled or promised by this figure.'
                  : 'No equity is recorded on your file, so this is entirely a model — move the Shares slider to see what a holding would pay.'}
              </p>

              {simulating && (
                <Button variant="ghost" size="sm" onClick={() => setSimulatedShares(null)}>
                  Use my {count(m.shares)} recorded shares
                </Button>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Your entry advantage</CardTitle>
                <CardDescription>Your holding against the same money at the latest price.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              {loading ? (
                <Skeleton className="h-24 w-full" />
              ) : m.extraPct === null ? (
                <EmptyState
                  title="No comparison available"
                  description="A comparison needs both an invested amount and a recorded price per share. Neither is on your file yet."
                />
              ) : (
                <>
                  <ComparisonBar
                    label="Your shares"
                    value={m.shares}
                    max={Math.max(m.shares, m.publicEquivalent)}
                    emphasis
                  />
                  <ComparisonBar
                    label="Same money at latest price"
                    value={Math.round(m.publicEquivalent)}
                    max={Math.max(m.shares, m.publicEquivalent)}
                  />
                  <div className="rounded-lg bg-elevated p-4">
                    <p className="text-xs uppercase tracking-wide text-muted-foreground">
                      Extra shares
                    </p>
                    <p className="tabular mt-1 text-xl font-semibold">
                      +{count(Math.round(m.extraShares))}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      +{m.extraPct.toFixed(1)}% more than the latest recorded price would buy
                    </p>
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          {/* The prototype's upsell card. Its package names, share counts and
              "+100% More Shares" claim had no source, and its button opened an
              external shop in a proxied iframe. This one points at the
              investments domain, which is a route in this app. */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Increase your position</CardTitle>
                <CardDescription>Open offerings are listed in the investments domain.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="text-sm text-muted-foreground">
                There is no package catalogue in this system, so no tiers, prices or inventory counts
                are shown here. What is open for application lives on the offerings screen.
              </p>
              <Button asChild>
                <Link to="/investments">
                  View offerings
                  <ArrowUpRight aria-hidden="true" />
                </Link>
              </Button>
            </CardContent>
          </Card>

          <NoticesPanel />
        </aside>
      </div>

      <RoundTermsModal open={termsOpen} onClose={() => setTermsOpen(false)} metrics={m} />
    </>
  );
}
