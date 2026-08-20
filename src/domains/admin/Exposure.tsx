import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Lock, RefreshCw, Search, ShieldCheck } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money } from '@/lib/format';
import { useBulkProfileStatus, useExposureIndex, useSetProfileStatus } from './hooks';
import {
  EXPOSURE_THRESHOLDS,
  MIN_EXPOSURE_USD,
  exposureToCsv,
  type ExposureLevel,
  type ExposureRow,
} from './lib/platformExposure';
import {
  ExportButton,
  LevelBadge,
  SafeModeBanner,
  ScanCoverage,
  UnpricedList,
  downloadCsv,
} from './components';

/**
 * Per-member exposure.
 *
 * The one screen that answers "who is holding what". Quarantine and release are
 * available here and are NOT behind safe mode: neither moves money, and the
 * ability to stop an account transacting has to survive a console that is
 * locked down against pushes. Correcting a position does move money, so it
 * lives on its own screen behind the typed confirmation.
 *
 * At most 500 rows are rendered. The CSV export carries the full filtered set —
 * a table nobody can scroll is not a safeguard against a list that is too long,
 * it is just a slower browser.
 */

const ROW_CAP = 500;
const LEVELS: (ExposureLevel | 'all')[] = ['all', 'critical', 'high', 'medium', 'low'];

const usdFormat = (value: number) => money(value, 'USD');
const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error ? error.message : fallback;

/** A segmented control. v3 has no Select, and for five options it needs none. */
function Segmented<T extends string | number>({
  label,
  options,
  value,
  onChange,
  render,
}: {
  label: string;
  options: readonly T[];
  value: T;
  onChange: (next: T) => void;
  render: (option: T) => string;
}) {
  return (
    <div className="flex flex-wrap items-center gap-1" role="group" aria-label={label}>
      {options.map((option) => (
        <Button
          key={String(option)}
          size="sm"
          variant={option === value ? 'primary' : 'ghost'}
          aria-pressed={option === value}
          onClick={() => onChange(option)}
        >
          {render(option)}
        </Button>
      ))}
    </div>
  );
}

export default function Exposure() {
  const [minUsd, setMinUsd] = useState<number>(MIN_EXPOSURE_USD);
  const [search, setSearch] = useState('');
  const [level, setLevel] = useState<ExposureLevel | 'all'>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const exposure = useExposureIndex(minUsd);
  const setStatus = useSetProfileStatus();
  const bulkStatus = useBulkProfileStatus();

  const rows = useMemo(() => exposure.data?.rows ?? [], [exposure.data]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return rows.filter((row) => {
      if (level !== 'all' && row.level !== level) return false;
      if (!query) return true;
      return [row.name, row.email, row.domain, row.userId].some((field) =>
        String(field).toLowerCase().includes(query)
      );
    });
  }, [rows, search, level]);

  const visible = filtered.slice(0, ROW_CAP);
  const selectedRows = useMemo(
    () => filtered.filter((row) => selected.has(row.userId)),
    [filtered, selected]
  );

  const toggleRow = (userId: string) =>
    setSelected((previous) => {
      const next = new Set(previous);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });

  const runSingle = (row: ExposureRow, status: 'suspended' | 'approved') => {
    setStatus.mutate(
      {
        userId: row.userId,
        status,
        fullName: row.name === '—' ? null : row.name,
        email: row.email === '—' ? null : row.email,
      },
      {
        onSuccess: () =>
          toast.success(
            status === 'suspended'
              ? `${row.name} quarantined.`
              : `${row.name} released back to approved.`
          ),
        onError: (error) => toast.error(errorMessage(error, 'The status change was refused.')),
      }
    );
  };

  const runBulk = (status: 'suspended' | 'approved') => {
    const ids = selectedRows.map((row) => row.userId);
    if (ids.length === 0) return;

    bulkStatus.mutate(
      {
        userIds: ids,
        status,
        reason: `Risk console bulk ${status === 'suspended' ? 'quarantine' : 'release'}`,
      },
      {
        onSuccess: (outcome) => {
          setSelected(new Set());
          toast.success(
            `${outcome.updated} account(s) ${status === 'suspended' ? 'quarantined' : 'released'}.`,
            outcome.failed > 0
              ? { description: `${outcome.failed} could not be changed and were left alone.` }
              : undefined
          );
        },
        onError: (error) => toast.error(errorMessage(error, 'The bulk change was refused.')),
      }
    );
  };

  const busy = setStatus.isPending || bulkStatus.isPending;

  return (
    <>
      <PageHeader
        title="Member exposure"
        description="One record per member, swept from every asset-bearing table. Holdings in a unit this platform has no rate for are listed unconverted, never as dollars."
        actions={
          <div className="flex gap-2">
            <Button
              variant="ghost"
              size="icon"
              aria-label="Re-run the exposure sweep"
              onClick={() => void exposure.refetch()}
              disabled={exposure.isFetching}
            >
              <RefreshCw className={exposure.isFetching ? 'animate-spin' : ''} />
            </Button>
            <ExportButton
              disabled={filtered.length === 0}
              onExport={() => {
                downloadCsv(
                  `platform-exposure-${new Date().toISOString().slice(0, 10)}.csv`,
                  exposureToCsv(filtered)
                );
                toast.success(`${filtered.length} row(s) exported.`);
              }}
            />
          </div>
        }
      />

      <SafeModeBanner />

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>
              {filtered.length} member{filtered.length === 1 ? '' : 's'} at or above{' '}
              {usdFormat(minUsd)}
            </CardTitle>
            <CardDescription>
              Accounts below the threshold are excluded — unless their unbacked positions alone
              clear it, or they hold something with no USD rate, which are the cases worth
              looking at.
            </CardDescription>
          </div>
        </CardHeader>

        <CardContent className="space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative min-w-[16rem] flex-1">
              <Search
                className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden="true"
              />
              <Input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search name, email, str.domain or user id"
                aria-label="Search members"
                className="pl-9"
              />
            </div>
            <Segmented
              label="Risk level"
              options={LEVELS}
              value={level}
              onChange={setLevel}
              render={(option) => (option === 'all' ? 'All levels' : option)}
            />
          </div>

          <Segmented
            label="Minimum exposure"
            options={EXPOSURE_THRESHOLDS}
            value={minUsd}
            onChange={setMinUsd}
            render={(option) => `≥ ${usdFormat(option)}`}
          />

          <div className="flex flex-wrap items-center gap-2 rounded-md bg-elevated p-3">
            <span className="mr-1 text-sm font-medium">
              {selectedRows.length} selected
            </span>
            <Button
              size="sm"
              variant="outline"
              disabled={busy || visible.length === 0}
              onClick={() => setSelected(new Set(visible.map((row) => row.userId)))}
            >
              Select visible
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() =>
                setSelected(
                  new Set(filtered.filter((row) => row.unbackedUsd >= 10_000).map((r) => r.userId))
                )
              }
            >
              Select unbacked ≥ {usdFormat(10_000)}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={busy || selected.size === 0}
              onClick={() => setSelected(new Set())}
            >
              Clear
            </Button>
            <div className="flex-1" />
            <Button
              size="sm"
              variant="danger"
              disabled={busy || selectedRows.length === 0}
              onClick={() => runBulk('suspended')}
            >
              <Lock />
              Quarantine selected
            </Button>
            <Button
              size="sm"
              variant="secondary"
              disabled={busy || selectedRows.length === 0}
              onClick={() => runBulk('approved')}
            >
              <ShieldCheck />
              Release selected
            </Button>
          </div>
        </CardContent>

        <CardContent className="p-0">
          {exposure.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-80 w-full" />
            </div>
          ) : exposure.isError ? (
            <ErrorState error={exposure.error} onRetry={() => void exposure.refetch()} />
          ) : filtered.length === 0 ? (
            <EmptyState
              title="No member matches"
              description={`No account reaches ${usdFormat(minUsd)} of exposure or unbacked value under this filter.`}
            />
          ) : (
            <>
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH className="w-8" />
                      <TH>Risk</TH>
                      <TH>Member</TH>
                      <TH className="text-right">
                        Exposure
                        <span className="block text-[10px] font-normal normal-case tracking-normal">
                          US$ only — unconverted shown below
                        </span>
                      </TH>
                      <TH className="text-right">Vouchers</TH>
                      <TH className="text-right">Fiat / crypto</TH>
                      <TH className="text-right">
                        Positions
                        <span className="block text-[10px] font-normal normal-case tracking-normal">
                          admin credit is the truth
                        </span>
                      </TH>
                      <TH className="text-right">Equity / raises / nodes</TH>
                      <TH>Signals</TH>
                      <TH className="text-right">Action</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {visible.map((row) => (
                      <TR key={row.userId}>
                        <TD>
                          <input
                            type="checkbox"
                            className="size-4 rounded border-border accent-primary"
                            checked={selected.has(row.userId)}
                            onChange={() => toggleRow(row.userId)}
                            aria-label={`Select ${row.name}`}
                          />
                        </TD>
                        <TD>
                          <LevelBadge level={row.level} score={row.score} />
                        </TD>
                        <TD>
                          <p className="font-medium">{row.name}</p>
                          <p className="text-xs text-muted-foreground">{row.email}</p>
                          <p className="text-xs text-muted-foreground">{row.domain}</p>
                          <div className="mt-1">
                            <StatusBadge status={row.accountStatus} />
                          </div>
                        </TD>
                        <TD className="tabular text-right font-semibold">
                          {usdFormat(row.totalUsd)}
                          {/* EUR / CHF / GBP and unpriced pool types. Not added
                              to the figure above, because nothing here can
                              convert them. */}
                          <UnpricedList items={row.unpriced} />
                        </TD>
                        <TD className="tabular text-right">
                          {usdFormat(row.breakdown.pendingVouchers)}
                          <span className="block text-xs text-muted-foreground">
                            {row.uncreditedCount}/{row.voucherCount} uncredited
                          </span>
                        </TD>
                        <TD className="tabular text-right">
                          {usdFormat(row.breakdown.fiat)}
                          <span className="block text-xs text-muted-foreground">
                            {usdFormat(row.breakdown.crypto)} crypto
                          </span>
                          {row.unpriced.length > 0 && (
                            <span className="block text-xs text-muted-foreground">
                              no USD rate for {row.unpriced.map((u) => u.unit).join(', ')}
                            </span>
                          )}
                        </TD>
                        <TD className="tabular text-right">
                          {usdFormat(row.breakdown.staking)}
                          <span className="block text-xs text-muted-foreground">
                            {usdFormat(row.breakdown.shares)} shares ·{' '}
                            {usdFormat(row.breakdown.vesting)} vesting
                          </span>
                          <span className="block text-xs text-muted-foreground">
                            credited {usdFormat(row.adminCreditedUsd)}
                          </span>
                          {row.unbackedUsd > 0 && (
                            <span className="block text-xs font-medium text-danger">
                              {usdFormat(row.unbackedUsd)} unbacked
                            </span>
                          )}
                        </TD>
                        <TD className="tabular text-right">
                          {usdFormat(row.breakdown.safeEquity)}
                          <span className="block text-xs text-muted-foreground">
                            {usdFormat(row.breakdown.subscriptions)} raises ·{' '}
                            {usdFormat(row.breakdown.nodes)} nodes
                          </span>
                          <span className="block text-xs text-muted-foreground">
                            {usdFormat(row.breakdown.guardian)} vault ·{' '}
                            {usdFormat(row.breakdown.cards)} cards
                          </span>
                        </TD>
                        <TD className="max-w-xs">
                          <p className="text-xs text-muted-foreground">{row.signals.join(' · ')}</p>
                        </TD>
                        <TD className="text-right">
                          {row.accountStatus === 'suspended' ? (
                            <Button
                              size="sm"
                              variant="outline"
                              disabled={busy}
                              onClick={() => runSingle(row, 'approved')}
                            >
                              <ShieldCheck />
                              Release
                            </Button>
                          ) : (
                            <Button
                              size="sm"
                              variant="danger"
                              disabled={busy}
                              onClick={() => runSingle(row, 'suspended')}
                            >
                              <Lock />
                              Quarantine
                            </Button>
                          )}
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>

              {filtered.length > ROW_CAP && (
                <p className="px-5 py-3 text-xs text-muted-foreground">
                  Showing the top {ROW_CAP} of {filtered.length}. Export the CSV for the full list.
                </p>
              )}
            </>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Sweep coverage</CardTitle>
            <CardDescription>Which tables this list was built from.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          {exposure.data && (
            <p className="rounded-md border border-border bg-elevated p-3 text-xs text-muted-foreground">
              {exposure.data.unpricedTotals.length > 0 ? (
                <>
                  Not converted to USD, because this platform has no rate for them:{' '}
                  <span className="font-medium text-foreground">
                    {exposure.data.unpricedTotals
                      .map(
                        (item) =>
                          `${item.amount.toLocaleString('en-IE', { maximumFractionDigits: 2 })} ${item.unit}`
                      )
                      .join(' · ')}
                  </span>
                  . These are excluded from every US$ figure on this page.
                </>
              ) : (
                'Every holding on this page had a USD rate. Nothing was excluded as unconverted.'
              )}{' '}
              BTC{' '}
              {exposure.data.rates.btcUsd === null
                ? 'could not be priced on this run and was left unconverted.'
                : `priced at ${usdFormat(exposure.data.rates.btcUsd)} from the btc-price feed — the same figure /guardian/reserves uses.`}{' '}
              ETH{' '}
              {exposure.data.rates.ethUsd === null
                ? 'could not be priced on this run and was left unconverted.'
                : `priced at ${usdFormat(exposure.data.rates.ethUsd)} from the crypto-prices feed — the same figure /admin uses.`}
            </p>
          )}
          {exposure.data ? (
            <ScanCoverage
              scannedTables={exposure.data.scannedTables}
              scannedRows={exposure.data.scannedRows}
              truncatedTables={exposure.data.truncatedTables}
                coverage={exposure.data.coverage}
              errors={exposure.data.errors}
              ranAt={exposure.data.ranAt}
            />
          ) : (
            <Skeleton className="h-12 w-full" />
          )}
        </CardContent>
      </Card>
    </>
  );
}
