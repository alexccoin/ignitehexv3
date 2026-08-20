import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  BadgeCheck,
  Banknote,
  Coins,
  FileStack,
  Globe,
  Hourglass,
  Layers,
  TrendingUp,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { CompositionChart, TrendChart } from '@/components/ui/charts';
import { useFiatWallets, useStakingPools, useV2Account } from '@/hooks/data';
import { money, shortDate, token } from '@/lib/format';
import {
  AllocationDetailModal,
  RowsSkeleton,
  SUPPLY_NOTE,
  count,
  ownershipPct,
  usd,
} from './components';
import {
  useArssWallet,
  useCryptoWallets,
  useDomeEquity,
  useDomeReach,
  useVestingSchedules,
  type AllocationRecord,
} from './hooks';

/**
 * The Dome portfolio.
 *
 * The prototype's `PortfolioSections`: the growth chart with its stat strip,
 * the package detail panel, the allocation table and the holdings list. Its
 * charts were literal SVG paths — `M120 202L340 146L560 80` with labels reading
 * $93,750 / $156,250 / $312,500 at listing prices of $3 / $5 / $10 — so the
 * "Profit Projection at Public Listing" panel drew the same three points for
 * every member regardless of what they held.
 *
 * That projection panel is gone. There is no listing price, no listing date and
 * no scenario table anywhere in this schema, and a projection is exactly the
 * kind of figure that must not be invented. The growth chart survives, plotting
 * the member's own cumulative investment, and the holdings composition is drawn
 * from their own balances.
 */
export default function DomePortfolio() {
  const equity = useDomeEquity();
  const pools = useStakingPools();
  const fiat = useFiatWallets();
  const crypto = useCryptoWallets();
  const arss = useArssWallet();
  const vesting = useVestingSchedules();
  const reach = useDomeReach();
  const v2 = useV2Account();

  const [selected, setSelected] = useState<AllocationRecord | null>(null);

  const m = equity.metrics;
  const positions = pools.data?.positions ?? [];
  const verified = v2.data?.assets ?? [];
  const openClaims = (v2.data?.claims ?? []).filter((c) => c.status !== 'approved');

  /**
   * Quantities per token, for the composition chart.
   *
   * Deliberately not summed into a portfolio total. `src/lib/balances.ts`
   * records why: the platform's own price endpoint returns a random number, so
   * any cross-token total built on it would be fiction. Each bar is one token in
   * its own units, and the caption says so.
   */
  const composition = useMemo(() => {
    const rows = positions.map((p) => ({ label: p.token.toUpperCase(), value: p.total }));
    for (const wallet of crypto.data ?? []) {
      const value = Number(wallet.balance ?? 0);
      if (value <= 0) continue;
      const label = (wallet.token_type ?? '').toUpperCase();
      const existing = rows.find((r) => r.label === label);
      if (existing) existing.value += value;
      else rows.push({ label, value });
    }
    const arssBalance = Number(arss.data?.arss_balance ?? 0);
    if (arssBalance > 0) {
      const existing = rows.find((r) => r.label === 'ARSS');
      if (existing) existing.value += arssBalance;
      else rows.push({ label: 'ARSS', value: arssBalance });
    }
    return rows.filter((r) => r.value > 0).sort((a, b) => b.value - a.value);
  }, [positions, crypto.data, arss.data]);

  const loading = equity.isLoading;

  return (
    <>
      <PageHeader
        title="Portfolio"
        description="Every equity allocation, token position and vesting schedule recorded against your file."
        actions={
          <Button variant="secondary" asChild>
            <Link to="/dome">Back to overview</Link>
          </Button>
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Shares held"
          value={count(m.shares)}
          sub={`${ownershipPct(m.ownership)} ${SUPPLY_NOTE}`}
          icon={<Layers className="size-4" />}
          loading={loading}
        />
        <Stat
          label="Total invested"
          value={m.invested > 0 ? usd(m.invested) : '—'}
          sub={`${m.counted.length} settled record${m.counted.length === 1 ? '' : 's'}`}
          icon={<Banknote className="size-4" />}
          loading={loading}
        />
        <Stat
          label="Indicative equity value"
          value={m.price > 0 && m.hasEquity ? usd(m.value) : '—'}
          sub={
            m.roi === null
              ? 'No invested amount to compare'
              : `${m.roi >= 0 ? '+' : ''}${m.roi.toFixed(1)}% against what you paid`
          }
          tone={m.unrealised > 0 ? 'success' : m.unrealised < 0 ? 'danger' : 'default'}
          icon={<TrendingUp className="size-4" />}
          loading={loading}
        />
        <Stat
          label="Verified assets"
          value={verified.length}
          sub={`${openClaims.length} claim${openClaims.length === 1 ? '' : 's'} still open`}
          icon={<BadgeCheck className="size-4" />}
          loading={v2.isLoading}
        />
      </div>

      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="text-base">Portfolio growth</CardTitle>
              <CardDescription>Cumulative amount invested across settled allocations.</CardDescription>
            </div>
            <Badge tone="neutral">
              {m.cumulative.length} point{m.cumulative.length === 1 ? '' : 's'}
            </Badge>
          </CardHeader>
          <CardContent>
            {loading ? (
              <Skeleton className="h-48 w-full" />
            ) : equity.isError ? (
              <ErrorState error={equity.error} onRetry={equity.refetch} />
            ) : m.cumulative.length === 0 ? (
              <EmptyState
                title="Nothing to plot"
                description="This chart needs at least one settled allocation on your file."
              />
            ) : (
              <>
                <TrendChart data={m.cumulative} format={(v) => usd(v)} height={220} />
                <div className="mt-4 grid gap-3 sm:grid-cols-3">
                  <div>
                    <p className="text-xs text-muted-foreground">Invested</p>
                    <p className="tabular text-lg font-semibold">{usd(m.invested)}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Indicative value</p>
                    <p className="tabular text-lg font-semibold">{m.price > 0 ? usd(m.value) : '—'}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Return</p>
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
              <CardTitle className="text-base">Token holdings</CardTitle>
              <CardDescription>How much of each token you hold, in its own units.</CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            {pools.isLoading || crypto.isLoading ? (
              <Skeleton className="h-48 w-full" />
            ) : pools.isError ? (
              <ErrorState error={pools.error} onRetry={() => void pools.refetch()} />
            ) : composition.length === 0 ? (
              <EmptyState
                title="No token balances"
                description="Nothing is held in your staking pools or token wallets."
                icon={<Coins className="size-5" />}
              />
            ) : (
              <>
                <CompositionChart
                  data={composition}
                  format={(v) => count(v, 4)}
                  height={Math.max(160, composition.length * 34)}
                />
                <p className="mt-3 text-xs text-muted-foreground">
                  Quantities are not converted to a common currency and do not add up to a portfolio
                  total: there is no trustworthy price feed in this system to convert them with.
                </p>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Equity allocations. */}
      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle className="text-base">Equity allocations</CardTitle>
            <CardDescription>
              SAFE and private placement records. Unsettled records are listed but excluded from
              every total above.
            </CardDescription>
          </div>
          <Badge tone="neutral">
            {m.records.length} record{m.records.length === 1 ? '' : 's'}
          </Badge>
        </CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <RowsSkeleton />
          ) : equity.isError ? (
            <ErrorState error={equity.error} onRetry={equity.refetch} />
          ) : m.records.length === 0 ? (
            <EmptyState
              title="No allocations on file"
              description="Nothing has been booked to you under any equity programme."
              icon={<FileStack className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Programme</TH>
                    <TH>Date</TH>
                    <TH className="text-right">Shares</TH>
                    <TH className="text-right">Price / share</TH>
                    <TH className="text-right">Invested</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {m.records.map((record) => (
                    <TR key={record.id}>
                      <TD>
                        <button
                          type="button"
                          className="font-medium text-primary underline-offset-4 hover:underline"
                          onClick={() => setSelected(record)}
                        >
                          {record.programme}
                        </button>
                        {!record.counted && (
                          <p className="text-xs text-warning">Excluded from totals</p>
                        )}
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(record.date)}</TD>
                      <TD className="tabular text-right">
                        {count(record.shares + record.bonusShares)}
                      </TD>
                      <TD className="tabular text-right">
                        {record.pricePerShare > 0 ? usd(record.pricePerShare, 3) : '—'}
                      </TD>
                      <TD className="tabular text-right">
                        {record.invested > 0 ? usd(record.invested) : '—'}
                      </TD>
                      <TD>
                        <StatusBadge status={record.status} />
                      </TD>
                    </TR>
                  ))}
                  {m.wnftShares > 0 && (
                    <TR>
                      <TD className="font-medium">wNFT shares</TD>
                      <TD className="text-muted-foreground">On your share ledger</TD>
                      <TD className="tabular text-right">{count(m.wnftShares)}</TD>
                      <TD className="text-right text-muted-foreground">—</TD>
                      <TD className="text-right text-muted-foreground">—</TD>
                      <TD>
                        <Badge tone="neutral">No cost recorded</Badge>
                      </TD>
                    </TR>
                  )}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>

      {/* Token and cash positions. */}
      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="text-base">Token positions</CardTitle>
              <CardDescription>Liquid, staked and accrued, per token.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {pools.isLoading ? (
              <RowsSkeleton rows={3} />
            ) : pools.isError ? (
              <ErrorState error={pools.error} onRetry={() => void pools.refetch()} />
            ) : positions.length === 0 && (crypto.data ?? []).length === 0 ? (
              <EmptyState title="No token positions" description="No pool or wallet balances found." />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Token</TH>
                      <TH className="text-right">Liquid</TH>
                      <TH className="text-right">Staked</TH>
                      <TH className="text-right">Rewards</TH>
                      <TH className="text-right">Total</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {positions.map((p) => (
                      <TR key={p.token}>
                        <TD className="font-medium uppercase">{p.token}</TD>
                        <TD className="tabular text-right">{count(p.liquid, 4)}</TD>
                        <TD className="tabular text-right">{count(p.staked, 4)}</TD>
                        <TD className="tabular text-right">{count(p.rewards, 4)}</TD>
                        <TD className="tabular text-right font-medium">{count(p.total, 4)}</TD>
                      </TR>
                    ))}
                    {(crypto.data ?? [])
                      .filter((w) => Number(w.balance ?? 0) > 0)
                      .map((w) => (
                        <TR key={w.id}>
                          <TD className="font-medium uppercase">{w.token_type}</TD>
                          <TD className="tabular text-right">{count(Number(w.balance), 4)}</TD>
                          <TD className="text-right text-muted-foreground">—</TD>
                          <TD className="text-right text-muted-foreground">—</TD>
                          <TD className="tabular text-right font-medium">
                            {count(Number(w.balance), 4)}
                          </TD>
                        </TR>
                      ))}
                    {Number(arss.data?.arss_balance ?? 0) > 0 && (
                      <TR>
                        <TD className="font-medium">ARSS</TD>
                        <TD className="tabular text-right">
                          {count(Number(arss.data?.arss_balance), 4)}
                        </TD>
                        <TD className="text-right text-muted-foreground">—</TD>
                        <TD className="text-right text-muted-foreground">—</TD>
                        <TD className="tabular text-right font-medium">
                          {count(Number(arss.data?.arss_balance), 4)}
                        </TD>
                      </TR>
                    )}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="text-base">Cash balances</CardTitle>
              <CardDescription>Fiat wallets held against your account.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {fiat.isLoading ? (
              <RowsSkeleton rows={2} />
            ) : fiat.isError ? (
              <ErrorState error={fiat.error} onRetry={() => void fiat.refetch()} />
            ) : (fiat.data ?? []).length === 0 ? (
              <EmptyState
                title="No cash wallets"
                description="No fiat wallet has been opened on your account."
                icon={<Banknote className="size-5" />}
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Currency</TH>
                      <TH className="text-right">Balance</TH>
                      <TH className="text-right">Available</TH>
                      <TH className="text-right">Held</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(fiat.data ?? []).map((wallet) => (
                      <TR key={wallet.id}>
                        <TD className="font-medium">{wallet.currency}</TD>
                        <TD className="tabular text-right">
                          {money(Number(wallet.balance ?? 0), wallet.currency)}
                        </TD>
                        <TD className="tabular text-right">
                          {money(Number(wallet.available_balance ?? 0), wallet.currency)}
                        </TD>
                        <TD className="tabular text-right">
                          {money(Number(wallet.held_balance ?? 0), wallet.currency)}
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Vesting. */}
      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle className="text-base">Vesting schedules</CardTitle>
            <CardDescription>Locked allocations releasing into your staking pools.</CardDescription>
          </div>
          <Badge tone="neutral">
            {(vesting.data ?? []).length} schedule{(vesting.data ?? []).length === 1 ? '' : 's'}
          </Badge>
        </CardHeader>
        <CardContent className="p-0">
          {vesting.isLoading ? (
            <RowsSkeleton rows={3} />
          ) : vesting.isError ? (
            <ErrorState error={vesting.error} onRetry={() => void vesting.refetch()} />
          ) : (vesting.data ?? []).length === 0 ? (
            <EmptyState
              title="Nothing vesting"
              description="No locked allocation is scheduled to release to you."
              icon={<Hourglass className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Amount</TH>
                    <TH>Source</TH>
                    <TH>Starts</TH>
                    <TH>Unlocks</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {(vesting.data ?? []).map((row) => (
                    <TR key={row.id}>
                      <TD className="tabular font-medium">
                        {token(Number(row.amount ?? 0), row.token_type)}
                      </TD>
                      <TD className="text-muted-foreground">{row.source.replace(/_/g, ' ')}</TD>
                      <TD className="text-muted-foreground">{shortDate(row.vesting_start_date)}</TD>
                      <TD className="text-muted-foreground">{shortDate(row.vesting_end_date)}</TD>
                      <TD>
                        <StatusBadge status={row.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>

      {/* Verified assets, open claims and platform reach. */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="text-base">Verified assets</CardTitle>
              <CardDescription>Positions countersigned by compliance review.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {v2.isLoading ? (
              <RowsSkeleton rows={3} />
            ) : v2.isError ? (
              <ErrorState error={v2.error} onRetry={() => void v2.refetch()} />
            ) : verified.length === 0 ? (
              <EmptyState
                title="Nothing countersigned yet"
                description="Assets appear here once a reviewer has verified a claim."
                icon={<BadgeCheck className="size-5" />}
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Asset</TH>
                      <TH>Category</TH>
                      <TH className="text-right">Amount</TH>
                      <TH>Verified</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {verified.map((asset) => (
                      <TR key={asset.id}>
                        <TD className="font-medium">{asset.asset_label ?? asset.asset_symbol}</TD>
                        <TD className="text-muted-foreground">{asset.category}</TD>
                        <TD className="tabular text-right">{count(Number(asset.amount ?? 0), 4)}</TD>
                        <TD className="text-muted-foreground">{shortDate(asset.verified_at)}</TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>

        <div className="space-y-4">
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Open claims</CardTitle>
                <CardDescription>Declared, awaiting verification.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0">
              {v2.isLoading ? (
                <RowsSkeleton rows={2} />
              ) : openClaims.length === 0 ? (
                <EmptyState title="No open claims" description="Nothing is waiting on review." />
              ) : (
                <ul className="divide-y divide-border">
                  {openClaims.map((claim) => (
                    <li key={claim.id} className="flex items-center justify-between gap-3 p-4">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">
                          {claim.asset_label ?? claim.asset_symbol}
                        </p>
                        <p className="tabular text-xs text-muted-foreground">
                          {count(Number(claim.claimed_amount ?? 0), 4)} declared
                        </p>
                      </div>
                      <StatusBadge status={claim.status} />
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="text-base">Platform reach</CardTitle>
                <CardDescription>Your str.name footprint.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-2">
              {reach.isLoading ? (
                <Skeleton className="h-16 w-full" />
              ) : reach.isError ? (
                <ErrorState error={reach.error} onRetry={() => void reach.refetch()} />
              ) : (
                <>
                  <div className="flex items-center justify-between gap-3">
                    <span className="flex items-center gap-2 text-sm text-muted-foreground">
                      <Globe className="size-4" aria-hidden="true" />
                      Domains held
                    </span>
                    <span className="tabular font-semibold">{reach.data?.domains ?? 0}</span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-sm text-muted-foreground">Active listings</span>
                    <span className="tabular font-semibold">{reach.data?.listings ?? 0}</span>
                  </div>
                  <Button variant="ghost" size="sm" asChild className="mt-2">
                    <Link to="/marketplace/domains">Manage domains</Link>
                  </Button>
                </>
              )}
            </CardContent>
          </Card>
        </div>
      </div>

      <AllocationDetailModal record={selected} onClose={() => setSelected(null)} />
    </>
  );
}
