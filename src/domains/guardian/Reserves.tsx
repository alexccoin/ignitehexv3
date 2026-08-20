import { useMemo } from 'react';
import { Activity, AlertTriangle, Bitcoin, Network, RefreshCw, ShieldCheck } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { ChartLegend, CompositionChart } from '@/components/ui/charts';
import { money, token as fmtToken } from '@/lib/format';
import { btc, MempoolLink, shortAddress } from './shared';
import {
  reservesIncomplete,
  useBtcPrice,
  useChainReserves,
  useSafeguardWallets,
  useWithdrawalRequests,
} from './hooks';

/** Requests that still have a claim on the reserve. */
const OPEN_STATUSES = new Set(['pending', 'processing', 'approved']);

/**
 * Proof of reserve.
 *
 * The figure on this page is the figure the data source returned. v2's version
 * did the opposite: it took the balances from `btc-wallet-balances` and then
 * subtracted three withdrawal lists that were typed into the page — complete
 * with beneficiary names, invoice references and transaction hashes — before
 * rendering the result as the on-chain reserve. The number shown as "verified
 * on chain" was therefore one no block explorer would confirm, and the moment
 * one of those withdrawals actually settled the page double-counted it.
 *
 * Committed outflows still matter, so they are shown — read from
 * `guardian_withdrawal_requests`, in their own panel, clearly beside the
 * reserve rather than folded into it. Every address links out to mempool.space
 * so the reader can check the balance themselves, which is the only thing that
 * makes any of this a proof.
 */
export default function Reserves() {
  const reserves = useChainReserves();
  const price = useBtcPrice();
  const withdrawals = useWithdrawalRequests();
  const safeguards = useSafeguardWallets();

  const wallets = reserves.data?.wallets ?? [];
  const totals = reserves.data?.totals;
  const btcPrice = price.data ?? null;

  /**
   * An address the chain could not be read for is EXCLUDED from the chart, not
   * plotted at zero: a missing slice reads as missing, a zero-height slice
   * reads as an empty wallet. The banner above says how many are missing.
   */
  const composition = useMemo(
    () =>
      wallets
        .filter((w) => w.balance !== null && w.balance > 0)
        .map((w) => ({ label: w.name.replace(/^Liquidity Node /, ''), value: w.balance as number })),
    [wallets]
  );

  /**
   * Whether this refresh read every address.
   *
   * `btc-wallet-balances` used to report a failed fetch as `balance: 0`, so an
   * unreachable blockchain.info made this page state that the reserve holds
   * 0 BTC — under a heading promising the chain's own figures. The function now
   * returns null per unread address and null totals, and this page refuses to
   * print a reserve total while any address is missing.
   */
  const incomplete = reservesIncomplete(reserves.data);
  const failedCount =
    reserves.data?.totals.addresses_failed ?? wallets.filter((w) => w.balance === null).length;

  // Grouped by asset, because a reserve figure in BTC cannot absorb a claim
  // denominated in something else.
  const openClaims = useMemo(() => {
    const byAsset = new Map<string, { asset: string; amount: number; count: number }>();
    for (const w of withdrawals.data ?? []) {
      if (!OPEN_STATUSES.has(w.status)) continue;
      const entry = byAsset.get(w.asset_symbol) ?? { asset: w.asset_symbol, amount: 0, count: 0 };
      entry.amount += Number(w.amount ?? 0);
      entry.count += 1;
      byAsset.set(w.asset_symbol, entry);
    }
    return [...byAsset.values()].sort((a, b) => b.amount - a.amount);
  }, [withdrawals.data]);

  const totalBtc = totals?.total_btc ?? null;

  return (
    <>
      <PageHeader
        title="Proof of reserve"
        description="On-chain balances of the reserve wallets, exactly as the chain reports them."
        actions={
          <Button
            variant="secondary"
            size="sm"
            onClick={() => {
              void reserves.refetch();
              void price.refetch();
            }}
            disabled={reserves.isFetching}
          >
            <RefreshCw className={reserves.isFetching ? 'animate-spin' : undefined} />
            Re-check chain
          </Button>
        }
      />

      {incomplete && (
        <div
          role="alert"
          className="mb-6 flex items-start gap-3 rounded-lg border border-danger/30 bg-danger/10 p-4 text-sm"
        >
          <AlertTriangle className="mt-0.5 size-4 shrink-0 text-danger" aria-hidden="true" />
          <div>
            <p className="font-medium">
              {failedCount} reserve address{failedCount === 1 ? '' : 'es'} could not be read.
            </p>
            <p className="mt-1 text-muted-foreground">
              The reserve total is withheld until every address answers. It is not shown as a
              smaller number, and an address that did not answer is not shown as empty — a failed
              read and a drained wallet are different facts and this page will not conflate them.
              Re-check the chain, or verify each address on mempool.space directly.
            </p>
          </div>
        </div>
      )}

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Total held"
          value={btc(totalBtc)}
          sub={
            totalBtc === null
              ? /* Not "0 BTC": the reserve is unknown, not empty. */
                'Withheld — at least one address could not be read'
              : btcPrice
                ? `≈ ${money(totalBtc * btcPrice, 'USD')} at ${money(btcPrice, 'USD')}/BTC`
                : /* The price lookup failing must not turn into a $0 valuation. */
                  'Spot price unavailable — no conversion shown'
          }
          tone={totalBtc === null ? 'danger' : 'default'}
          icon={<Bitcoin className="size-4" />}
          loading={reserves.isLoading}
        />
        <Stat
          label="Reserve nodes"
          value={
            totals
              ? `${totals.active_nodes} of ${totals.addresses_total ?? wallets.length}`
              : '—'
          }
          sub="Addresses that answered this refresh"
          tone={incomplete ? 'warning' : 'default'}
          icon={<Network className="size-4" />}
          loading={reserves.isLoading}
        />
        <Stat
          label="SourceLess reserve"
          value={btc(totals?.sourceless_btc ?? null)}
          sub="As classified by the balance service"
          tone={totals && totals.sourceless_btc === null ? 'danger' : 'default'}
          icon={<ShieldCheck className="size-4" />}
          loading={reserves.isLoading}
        />
        <Stat
          label="CCoin reserve"
          value={btc(totals?.ccoin_btc ?? null)}
          sub="As classified by the balance service"
          tone={totals && totals.ccoin_btc === null ? 'danger' : 'default'}
          icon={<ShieldCheck className="size-4" />}
          loading={reserves.isLoading}
        />
      </div>

      <div className="mb-6 grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <div>
              <CardTitle>Reserve wallets</CardTitle>
              <CardDescription>
                Balances are reported by the chain and rendered unchanged. Nothing on this page is
                netted off before you see it — check any row against mempool.space. An address the
                chain could not be read for says so; it is never shown as zero.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="pt-3">
            {reserves.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : reserves.isError ? (
              <ErrorState
                title="Could not reach the chain"
                error={reserves.error}
                onRetry={() => void reserves.refetch()}
              />
            ) : wallets.length === 0 ? (
              <EmptyState
                icon={<Bitcoin className="size-5" />}
                title="No reserve wallets reported"
                description="The balance service returned no addresses for this refresh."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Node</TH>
                      <TH>Classification</TH>
                      <TH>Address</TH>
                      <TH className="text-right">Balance</TH>
                      <TH className="text-right">Verify</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {wallets.map((w) => (
                      <TR key={w.address}>
                        <TD className="font-medium">{w.name}</TD>
                        <TD className="text-muted-foreground">{w.type}</TD>
                        <TD className="font-mono text-xs text-muted-foreground">
                          {shortAddress(w.address)}
                        </TD>
                        <TD
                          className={
                            w.balance === null
                              ? 'whitespace-nowrap text-right font-medium text-danger'
                              : 'tabular whitespace-nowrap text-right font-medium'
                          }
                        >
                          {btc(w.balance)}
                          {w.balance === null && (
                            <span className="mt-0.5 block max-w-56 whitespace-normal break-words text-right text-xs font-normal text-muted-foreground">
                              {w.error ?? 'the chain could not be read for this address'}
                            </span>
                          )}
                        </TD>
                        <TD className="text-right">
                          <MempoolLink address={w.address} />
                        </TD>
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
            <div>
              <CardTitle>Distribution</CardTitle>
              <CardDescription>BTC held per reserve node.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 pt-3">
            {reserves.isLoading ? (
              <Skeleton className="h-48 w-full" />
            ) : reserves.isError ? (
              <ErrorState error={reserves.error} onRetry={() => void reserves.refetch()} />
            ) : composition.length === 0 ? (
              <EmptyState
                icon={<Activity className="size-5" />}
                title="Nothing to chart"
                description="No reserve wallet currently holds a balance."
              />
            ) : (
              <>
                <CompositionChart
                  data={composition}
                  height={Math.max(160, composition.length * 34)}
                  format={(v) => btc(v)}
                />
                <ChartLegend items={composition.map((c, i) => ({ label: c.label, index: i }))} />
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Committed outflows</CardTitle>
              <CardDescription>
                Withdrawal requests that still have a claim on the reserve, read from the database.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 pt-3">
            <p className="rounded-md border border-border bg-elevated p-3 text-xs text-muted-foreground">
              These amounts are <span className="font-medium text-foreground">not</span> subtracted
              from the balances above. A reserve figure is what the chain holds now; a request is a
              claim against it that has not settled. Presenting the difference as the on-chain
              balance would misstate both.
            </p>

            {withdrawals.isLoading ? (
              <>
                <Skeleton className="h-12 w-full" />
                <Skeleton className="h-12 w-full" />
              </>
            ) : withdrawals.isError ? (
              <ErrorState error={withdrawals.error} onRetry={() => void withdrawals.refetch()} />
            ) : openClaims.length === 0 ? (
              <EmptyState
                title="No open claims"
                description="No withdrawal request is currently pending, approved or processing."
              />
            ) : (
              openClaims.map((claim) => (
                <div
                  key={claim.asset}
                  className="flex items-center justify-between gap-4 rounded-lg border border-border p-3"
                >
                  <div className="min-w-0">
                    <p className="font-medium">{claim.asset}</p>
                    <p className="text-xs text-muted-foreground">
                      {claim.count} open request{claim.count === 1 ? '' : 's'}
                    </p>
                  </div>
                  <span className="tabular shrink-0 font-medium text-warning">
                    {fmtToken(claim.amount, claim.asset)}
                  </span>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div>
              <CardTitle>Registered safeguard wallets</CardTitle>
              <CardDescription>
                Reserve and cold-storage addresses on record, with the balance the database holds
                for each.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="pt-3">
            {safeguards.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : safeguards.isError ? (
              <ErrorState error={safeguards.error} onRetry={() => void safeguards.refetch()} />
            ) : (safeguards.data ?? []).length === 0 ? (
              <EmptyState
                title="No safeguard wallets registered"
                description="Nothing has been recorded in guardian_safeguard_wallets."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Wallet</TH>
                      <TH>Address</TH>
                      <TH className="text-right">Recorded balance</TH>
                      <TH className="text-right">Verify</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(safeguards.data ?? []).map((s) => (
                      <TR key={s.id}>
                        <TD>
                          <p className="font-medium">{s.wallet_name}</p>
                          <p className="text-xs text-muted-foreground">
                            {s.wallet_type} · {s.network}
                          </p>
                        </TD>
                        <TD className="font-mono text-xs text-muted-foreground">
                          {shortAddress(s.wallet_address)}
                        </TD>
                        <TD className="tabular whitespace-nowrap text-right">
                          {fmtToken(Number(s.balance ?? 0), s.asset_symbol)}
                        </TD>
                        <TD className="text-right">
                          <MempoolLink address={s.wallet_address} />
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

      {totals?.last_updated && (
        <p className="mt-6 text-xs text-muted-foreground">
          Chain balances last read {new Date(totals.last_updated).toLocaleString('en-IE')}.
        </p>
      )}
    </>
  );
}
