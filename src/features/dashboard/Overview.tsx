import { Link } from 'react-router-dom';
import { ArrowRight, Coins, ShieldCheck, Wallet as WalletIcon } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Stat } from '@/components/ui/stat';
import { Button } from '@/components/ui/button';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { Skeleton } from '@/components/ui/skeleton';
import { CompositionChart, TrendChart, ChartLegend } from '@/components/ui/charts';
import { useStakingPools, useTransactions, useV2Account, useFiatWallets } from '@/hooks/data';
import { token, money, relativeTime, shortDate } from '@/lib/format';
import { largestPosition, byToken } from '@/lib/balances';
import { useAuth } from '@/features/auth/AuthProvider';

export default function Overview() {
  const { user } = useAuth();
  const pools = useStakingPools();
  const txns = useTransactions(6);
  const v2 = useV2Account();
  const fiat = useFiatWallets();

  const positions = pools.data?.positions ?? [];
  const fiatTotal = (fiat.data ?? []).reduce((s, w) => s + Number(w.balance ?? 0), 0);
  const name = (user?.user_metadata?.full_name as string | undefined)?.split(' ')[0];
  const tokenCount = positions.length;
  const largest = largestPosition(positions);

  // Both charts derive from data already on screen rather than a second query,
  // so a chart can never disagree with the figures beside it.
  const composition = positions.map((p) => ({ label: p.token.toUpperCase(), value: p.total }));

  // Recent movement, oldest first so time reads left to right. When the whole
  // series falls on one day a date axis repeats the same label, so it drops to
  // time-of-day instead.
  const txRows = [...(txns.data ?? [])].reverse();
  const days = new Set(txRows.map((t) => (t.created_at ?? '').slice(0, 10)));
  const sameDay = days.size <= 1;
  const trend = txRows.map((t) => ({
    label: sameDay
      ? new Date(t.created_at ?? '').toLocaleTimeString('en-IE', {
          hour: '2-digit',
          minute: '2-digit',
        })
      : shortDate(t.created_at),
    value: Number(t.amount ?? 0),
  }));

  return (
    <>
      <PageHeader
        title={name ? `Welcome back, ${name}` : 'Overview'}
        description="Your holdings, positions and recent activity."
      />

      {v2.data?.account && v2.data.account.status !== 'approved' && (
        <Card className="mb-6 border-warning/30 bg-warning/5">
          <CardContent className="flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-start gap-3">
              <ShieldCheck className="mt-0.5 size-5 shrink-0 text-warning" />
              <div>
                <p className="font-medium">Verification not complete</p>
                <p className="text-sm text-muted-foreground">
                  Assets are credited only after your account and claims are verified.
                </p>
              </div>
            </div>
            <Button asChild variant="secondary" size="sm">
              <Link to="/account">
                Continue <ArrowRight />
              </Link>
            </Button>
          </CardContent>
        </Card>
      )}

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Largest holding"
          value={largest ? token(largest.total, largest.token) : '—'}
          sub={tokenCount === 1 ? '1 token held' : tokenCount + ' tokens held'}
          icon={<WalletIcon className="size-4" />}
          loading={pools.isLoading}
        />
        <Stat
          label="Staked"
          value={byToken(positions, 'staked', token)}
          icon={<Coins className="size-4" />}
          loading={pools.isLoading}
        />
        <Stat label="Fiat balance" value={money(fiatTotal)} loading={fiat.isLoading} />
        <Stat
          label="Verified assets"
          value={String(v2.data?.assets.length ?? 0)}
          sub={v2.data?.claims.length ? v2.data.claims.length + ' claims submitted' : undefined}
          tone="primary"
          loading={v2.isLoading}
        />
      </div>

      {(composition.length > 0 || trend.length > 0) && (
        <div className="mb-6 grid gap-6 lg:grid-cols-2">
          {composition.length > 0 && (
            <Card>
              <CardHeader>
                <div>
                  <CardTitle>Holdings by token</CardTitle>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Each token is labelled, so the chart reads without colour.
                  </p>
                </div>
              </CardHeader>
              <CardContent className="space-y-3 pt-3">
                <CompositionChart data={composition} format={(v) => v.toLocaleString()} />
                <ChartLegend items={composition.map((c, i) => ({ label: c.label, index: i }))} />
              </CardContent>
            </Card>
          )}

          {trend.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>Recent movement</CardTitle>
              </CardHeader>
              <CardContent className="pt-3">
                <TrendChart data={trend} colorIndex={1} format={(v) => v.toLocaleString()} />
              </CardContent>
            </Card>
          )}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Recent activity</CardTitle>
            <Button asChild variant="ghost" size="sm">
              <Link to="/wallet">View all</Link>
            </Button>
          </CardHeader>
          <CardContent className="pt-3">
            {txns.isLoading ? (
              <div className="space-y-2">
                {[0, 1, 2].map((i) => (
                  <Skeleton key={i} className="h-10 w-full" />
                ))}
              </div>
            ) : txns.isError ? (
              <ErrorState error={txns.error} onRetry={() => void txns.refetch()} />
            ) : (txns.data ?? []).length === 0 ? (
              <EmptyState
                title="No transactions yet"
                description="Activity will appear here once you transact."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Token</TH>
                      <TH>Amount</TH>
                      <TH>Status</TH>
                      <TH>When</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(txns.data ?? []).map((t) => (
                      <TR key={t.id}>
                        <TD className="font-medium uppercase">{t.token_type}</TD>
                        <TD className="tabular">{token(Number(t.amount), t.token_type ?? '')}</TD>
                        <TD>
                          <StatusBadge status={t.status} />
                        </TD>
                        <TD className="text-muted-foreground">{relativeTime(t.created_at)}</TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Positions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3 pt-3">
            {pools.isLoading ? (
              [0, 1].map((i) => <Skeleton key={i} className="h-14 w-full" />)
            ) : positions.length === 0 ? (
              <EmptyState title="No positions" description="Stake tokens to open a position." />
            ) : (
              positions.map((p) => (
                <div key={p.token} className="rounded-lg border border-border p-3">
                  <div className="flex items-center justify-between">
                    <span className="font-medium uppercase">{p.token}</span>
                    <span className="tabular text-sm">{token(p.total, p.token)}</span>
                  </div>
                  <div className="mt-1 flex gap-4 text-xs text-muted-foreground">
                    <span>Liquid {token(p.liquid, p.token)}</span>
                    <span>Staked {token(p.staked, p.token)}</span>
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
