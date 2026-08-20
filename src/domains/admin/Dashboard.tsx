import { useMemo } from 'react';
import { Link } from 'react-router-dom';
import { Layers, RefreshCw, ShieldAlert, TrendingUp, Users } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ChartLegend, CompositionChart } from '@/components/ui/charts';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money } from '@/lib/format';
import { useExposureIndex, useRiskScan } from './hooks';
import { compositionOf, levelCounts, type ExposureLevel } from './lib/platformExposure';
import { severityCounts, type RiskSeverity } from './lib/platformRiskScan';
import { LevelBadge, SafeModeBanner, ScanCoverage, UnpricedList } from './components';

/**
 * The console index.
 *
 * One question: how much value is the platform carrying, and how much of it is
 * backed by a decision somebody actually made? Everything else in this domain
 * is a way of acting on the answer.
 *
 * The two figures at the top are deliberately not summed together. Exposure is
 * value the platform owes and can account for. Unbacked positions are balances
 * sitting in staking, share and vesting tables with no credited voucher,
 * approved raise or admin-approved staking request behind them — they are
 * excluded from exposure precisely because counting them would legitimise them.
 *
 * The exposure figure is a US DOLLAR figure over dollar-denominated holdings.
 * It used to be four currencies added together: EUR, CHF and GBP were valued at
 * 1.00 USD each, so `US$151,177.82` was a sum of numerals in four units. Those
 * currencies have no rate here, so they are reported unconverted beneath the
 * tile and are not in the total.
 */

const usdFormat = (value: number) => money(value, 'USD');

export default function AdminDashboard() {
  const exposure = useExposureIndex();
  const risk = useRiskScan();

  const rows = useMemo(() => exposure.data?.rows ?? [], [exposure.data]);
  const composition = useMemo(() => compositionOf(rows), [rows]);
  const levels = useMemo(() => levelCounts(rows), [rows]);
  const severities = useMemo(
    () => severityCounts(risk.data?.findings ?? []),
    [risk.data]
  );

  const severityData = (['critical', 'high', 'medium', 'low'] as RiskSeverity[])
    .map((severity) => ({ label: severity, value: severities[severity] }))
    .filter((entry) => entry.value > 0);

  const criticalAndHigh = levels.critical + levels.high;
  const topExposed = rows.slice(0, 10);

  // Holdings with no USD rate. Kept out of `totalExposureUsd` and shown in
  // their own units, because there is no exchange rate in this system to
  // convert them with and printing them as dollars is what this replaces.
  const unpricedTotals = exposure.data?.unpricedTotals ?? [];
  const btcUsd = exposure.data?.rates.btcUsd ?? null;
  const ethUsd = exposure.data?.rates.ethUsd ?? null;

  return (
    <>
      <PageHeader
        title="Risk console"
        description="Every asset-bearing table in the platform, valued in USD per member."
        actions={
          <Button
            variant="secondary"
            onClick={() => {
              void exposure.refetch();
              void risk.refetch();
            }}
            disabled={exposure.isFetching || risk.isFetching}
          >
            <RefreshCw className={exposure.isFetching || risk.isFetching ? 'animate-spin' : ''} />
            Re-scan
          </Button>
        }
      />

      <SafeModeBanner />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Backed exposure"
          value={usdFormat(exposure.data?.totalExposureUsd ?? 0)}
          sub={
            unpricedTotals.length > 0
              ? 'US$-denominated holdings only — see unconverted below'
              : 'Value the platform can account for'
          }
          loading={exposure.isLoading}
          icon={<TrendingUp className="size-4" />}
        />
        <Stat
          label="Unbacked positions"
          value={usdFormat(exposure.data?.totalUnbackedUsd ?? 0)}
          sub="Staking, shares and vesting with no admin credit"
          loading={exposure.isLoading}
          tone={(exposure.data?.totalUnbackedUsd ?? 0) > 0 ? 'danger' : 'default'}
          icon={<ShieldAlert className="size-4" />}
        />
        <Stat
          label="Members holding assets"
          value={(exposure.data?.totalMembers ?? 0).toLocaleString()}
          sub={`${rows.length} above the ${usdFormat(exposure.data?.minUsd ?? 0)} threshold`}
          loading={exposure.isLoading}
          icon={<Users className="size-4" />}
        />
        <Stat
          label="Critical or high"
          value={criticalAndHigh}
          sub={`${risk.data?.findings.length ?? 0} open risk findings`}
          loading={exposure.isLoading}
          tone={criticalAndHigh > 0 ? 'warning' : 'default'}
          icon={<Layers className="size-4" />}
        />
      </div>

      {exposure.data && (
        <div className="mb-6 rounded-lg border border-border bg-elevated p-4 text-sm">
          {unpricedTotals.length > 0 ? (
            <p className="text-muted-foreground">
              <span className="font-medium text-foreground">Not in the figures above:</span>{' '}
              <span className="tabular font-medium text-warning">
                {unpricedTotals
                  .map(
                    (item) =>
                      `${item.amount.toLocaleString('en-IE', { maximumFractionDigits: 2 })} ${item.unit}`
                  )
                  .join(' · ')}
              </span>
              . This platform has no exchange rate for these units, so they are reported as
              quantities rather than converted into the US$ totals.
            </p>
          ) : (
            <p className="text-muted-foreground">
              Every holding swept had a USD rate — nothing was excluded as unconverted.
            </p>
          )}
          <p className="mt-1 text-xs text-muted-foreground">
            {btcUsd === null
              ? 'The BTC price feed did not answer on this run, so any BTC holding is reported unconverted rather than valued from a constant.'
              : `BTC valued at ${usdFormat(btcUsd)} from the btc-price feed — one source, shared with /guardian/reserves.`}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            {ethUsd === null
              ? 'The ETH price feed did not answer on this run, so any ETH holding is reported unconverted rather than valued from a constant.'
              : `ETH valued at ${usdFormat(ethUsd)} from the crypto-prices feed — one source, shared with /admin/exposure and /admin/risk.`}
          </p>
        </div>
      )}

      <div className="mb-6 grid gap-6 lg:grid-cols-2 lg:items-start">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Exposure composition</CardTitle>
              <CardDescription>
                USD held per asset class, across every member above the threshold.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            {exposure.isLoading ? (
              <Skeleton className="h-52 w-full" />
            ) : exposure.isError ? (
              <ErrorState error={exposure.error} onRetry={() => void exposure.refetch()} />
            ) : composition.length === 0 ? (
              <EmptyState
                title="No exposure recorded"
                description="No member holds a valued asset in any swept table."
              />
            ) : (
              <>
                <CompositionChart data={composition} format={usdFormat} height={Math.max(160, composition.length * 26)} />
                <ChartLegend items={composition.map((entry, index) => ({ label: entry.label, index }))} />
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Risk findings by severity</CardTitle>
              <CardDescription>
                Strange or risky operations found across the asset tables.
              </CardDescription>
            </div>
            <Button asChild variant="ghost" size="sm">
              <Link to="/admin/risk">Triage</Link>
            </Button>
          </CardHeader>
          <CardContent>
            {risk.isLoading ? (
              <Skeleton className="h-52 w-full" />
            ) : risk.isError ? (
              <ErrorState error={risk.error} onRetry={() => void risk.refetch()} />
            ) : severityData.length === 0 ? (
              <EmptyState
                title="Nothing flagged"
                description="No finding cleared the materiality bar on this scan."
              />
            ) : (
              <>
                <CompositionChart
                  data={severityData}
                  format={(value) => `${value} finding${value === 1 ? '' : 's'}`}
                  height={Math.max(140, severityData.length * 34)}
                />
                <ChartLegend items={severityData.map((entry, index) => ({ label: entry.label, index }))} />
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Most exposed members</CardTitle>
            <CardDescription>
              Ranked by backed exposure. Unbacked value is shown separately because it is
              excluded from the exposure figure.
            </CardDescription>
          </div>
          <Button asChild variant="secondary" size="sm">
            <Link to="/admin/exposure">Full list</Link>
          </Button>
        </CardHeader>
        <CardContent className="p-0">
          {exposure.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-64 w-full" />
            </div>
          ) : exposure.isError ? (
            <ErrorState error={exposure.error} onRetry={() => void exposure.refetch()} />
          ) : topExposed.length === 0 ? (
            <EmptyState
              title="No member above the threshold"
              description={`No account reaches ${usdFormat(exposure.data?.minUsd ?? 0)} of exposure or unbacked value.`}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Risk</TH>
                    <TH>Member</TH>
                    <TH className="text-right">Exposure</TH>
                    <TH className="text-right">Admin credit</TH>
                    <TH className="text-right">Unbacked</TH>
                    <TH>Top signal</TH>
                  </TR>
                </THead>
                <TBody>
                  {topExposed.map((row) => (
                    <TR key={row.userId}>
                      <TD>
                        <LevelBadge level={row.level as ExposureLevel} score={row.score} />
                      </TD>
                      <TD>
                        <p className="font-medium">{row.name}</p>
                        <p className="text-xs text-muted-foreground">{row.email}</p>
                      </TD>
                      <TD className="tabular text-right font-medium">
                        {usdFormat(row.totalUsd)}
                        <UnpricedList items={row.unpriced} />
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {usdFormat(row.adminCreditedUsd)}
                      </TD>
                      <TD className="tabular text-right">
                        {row.unbackedUsd > 0 ? (
                          <span className="font-medium text-danger">{usdFormat(row.unbackedUsd)}</span>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TD>
                      <TD className="max-w-xs">
                        <p className="truncate text-xs text-muted-foreground">{row.signals[0]}</p>
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
          <div className="space-y-1">
            <CardTitle>Sweep coverage</CardTitle>
            <CardDescription>
              What the last scan actually read. A total is only as good as its coverage.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {exposure.isLoading ? (
            <Skeleton className="h-16 w-full" />
          ) : exposure.isError ? (
            <ErrorState error={exposure.error} onRetry={() => void exposure.refetch()} />
          ) : exposure.data ? (
            <ScanCoverage
              scannedTables={exposure.data.scannedTables}
              scannedRows={exposure.data.scannedRows}
              truncatedTables={exposure.data.truncatedTables}
                coverage={exposure.data.coverage}
              errors={exposure.data.errors}
              ranAt={exposure.data.ranAt}
            />
          ) : null}
        </CardContent>
      </Card>
    </>
  );
}
