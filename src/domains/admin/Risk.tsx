import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { CheckCheck, RefreshCw, Search, Snowflake } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ChartLegend, CompositionChart } from '@/components/ui/charts';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import { useRiskScan } from './hooks';
import {
  SEVERITY_ORDER,
  categoryCounts,
  findingsToCsv,
  severityCounts,
  type RiskSeverity,
} from './lib/platformRiskScan';
import {
  ExportButton,
  LevelBadge,
  SafeModeBanner,
  ScanCoverage,
  UnavailableAction,
  downloadCsv,
} from './components';

/**
 * Risk triage.
 *
 * The radar reports what it found and stops. Nothing on this screen writes: a
 * finding is a reason to go and use one of the sanctioned routines on another
 * screen, not a button that "fixes" a row.
 *
 * Two rules govern what appears. Integrity breaches — a duplicated payment
 * proof, a reused transaction hash, a negative balance, a ledger that does not
 * add up — are always shown, at any value, because a $50 duplicate is the same
 * fraud as a $50,000 one. Everything else must clear $10,000 USD-equivalent, so
 * the queue stays a list of things worth an administrator's attention.
 */

const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error ? error.message : fallback;

const SEVERITY_FILTERS: (RiskSeverity | 'all')[] = ['all', ...SEVERITY_ORDER];

export default function Risk() {
  const [severity, setSeverity] = useState<RiskSeverity | 'all'>('all');
  const [category, setCategory] = useState<string>('all');
  const [search, setSearch] = useState('');

  const scan = useRiskScan();
  const findings = useMemo(() => scan.data?.findings ?? [], [scan.data]);

  const counts = useMemo(() => severityCounts(findings), [findings]);
  const categories = useMemo(() => categoryCounts(findings), [findings]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return findings.filter((finding) => {
      if (severity !== 'all' && finding.severity !== severity) return false;
      if (category !== 'all' && finding.category !== category) return false;
      if (!query) return true;
      return [finding.rule, finding.detail, finding.source, finding.userId, finding.reference].some(
        (field) => String(field ?? '').toLowerCase().includes(query)
      );
    });
  }, [findings, severity, category, search]);

  const severityData = SEVERITY_ORDER.map((level) => ({
    label: level,
    value: counts[level],
  })).filter((entry) => entry.value > 0);

  return (
    <>
      <PageHeader
        title="Risk findings"
        description="Strange or risky operations across every asset table, normalised for triage."
        actions={
          <div className="flex gap-2">
            <Button
              variant="ghost"
              size="icon"
              aria-label="Re-run the risk scan"
              onClick={() => void scan.refetch()}
              disabled={scan.isFetching}
            >
              <RefreshCw className={scan.isFetching ? 'animate-spin' : ''} />
            </Button>
            <ExportButton
              disabled={filtered.length === 0}
              onExport={() => {
                downloadCsv(
                  `platform-risk-findings-${new Date().toISOString().slice(0, 10)}.csv`,
                  findingsToCsv(filtered)
                );
                toast.success(`${filtered.length} finding(s) exported.`);
              }}
            />
          </div>
        }
      />

      <SafeModeBanner />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {SEVERITY_ORDER.map((level) => (
          <Stat
            key={level}
            label={level}
            value={counts[level]}
            loading={scan.isLoading}
            tone={level === 'critical' ? 'danger' : level === 'high' ? 'warning' : 'default'}
          />
        ))}
      </div>

      <div className="mb-6 grid gap-6 lg:grid-cols-2 lg:items-start">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>By severity</CardTitle>
              <CardDescription>How the open findings are distributed.</CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            {scan.isLoading ? (
              <Skeleton className="h-40 w-full" />
            ) : scan.isError ? (
              <ErrorState error={scan.error} onRetry={() => void scan.refetch()} />
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
                <ChartLegend
                  items={severityData.map((entry, index) => ({ label: entry.label, index }))}
                />
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>By asset class</CardTitle>
              <CardDescription>Where the findings are concentrated.</CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            {scan.isLoading ? (
              <Skeleton className="h-40 w-full" />
            ) : scan.isError ? (
              <ErrorState error={scan.error} onRetry={() => void scan.refetch()} />
            ) : categories.length === 0 ? (
              <EmptyState title="Nothing flagged" description="No asset class reported a finding." />
            ) : (
              <>
                <CompositionChart
                  data={categories}
                  format={(value) => `${value} finding${value === 1 ? '' : 's'}`}
                  height={Math.max(140, categories.length * 30)}
                />
                <ChartLegend
                  items={categories.map((entry, index) => ({ label: entry.label, index }))}
                />
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>
              {filtered.length} finding{filtered.length === 1 ? '' : 's'}
            </CardTitle>
            <CardDescription>
              Integrity breaches are listed at any value. Everything else clears $10,000
              USD-equivalent.
            </CardDescription>
          </div>
        </CardHeader>

        <CardContent className="space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative min-w-[16rem] flex-1">
              <Search
                className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden="true"
              />
              <Input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search rule, detail, table, member or reference"
                aria-label="Search findings"
                className="pl-9"
              />
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-1" role="group" aria-label="Severity">
            {SEVERITY_FILTERS.map((option) => (
              <Button
                key={option}
                size="sm"
                variant={option === severity ? 'primary' : 'ghost'}
                aria-pressed={option === severity}
                onClick={() => setSeverity(option)}
              >
                {option === 'all' ? 'All severities' : option}
              </Button>
            ))}
          </div>

          <div className="flex flex-wrap items-center gap-1" role="group" aria-label="Asset class">
            <Button
              size="sm"
              variant={category === 'all' ? 'primary' : 'ghost'}
              aria-pressed={category === 'all'}
              onClick={() => setCategory('all')}
            >
              All classes
            </Button>
            {categories.map((entry) => (
              <Button
                key={entry.label}
                size="sm"
                variant={category === entry.label ? 'primary' : 'ghost'}
                aria-pressed={category === entry.label}
                onClick={() => setCategory(entry.label)}
              >
                {entry.label}
                <Badge tone="neutral">{entry.value}</Badge>
              </Button>
            ))}
          </div>
        </CardContent>

        <CardContent className="p-0">
          {scan.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-80 w-full" />
            </div>
          ) : scan.isError ? (
            <ErrorState
              error={errorMessage(scan.error, 'The risk scan could not be run.')}
              onRetry={() => void scan.refetch()}
            />
          ) : filtered.length === 0 ? (
            <EmptyState
              title="Nothing to triage"
              description="No finding matches this filter."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Severity</TH>
                    <TH>Rule</TH>
                    <TH>Detail</TH>
                    <TH>Source</TH>
                    <TH>Member</TH>
                    <TH className="text-right">Amount</TH>
                    <TH>Seen</TH>
                  </TR>
                </THead>
                <TBody>
                  {filtered.map((finding) => (
                    <TR key={finding.id}>
                      <TD>
                        <LevelBadge level={finding.severity} />
                      </TD>
                      <TD>
                        <p className="font-medium">{finding.rule}</p>
                        <p className="text-xs text-muted-foreground">{finding.category}</p>
                      </TD>
                      <TD className="max-w-md">
                        <p className="text-sm text-muted-foreground">{finding.detail}</p>
                      </TD>
                      <TD className="font-mono text-xs text-muted-foreground">{finding.source}</TD>
                      <TD className="font-mono text-xs text-muted-foreground">
                        {finding.userId ? `${finding.userId.slice(0, 8)}…` : '—'}
                      </TD>
                      <TD className="tabular text-right">
                        {finding.amount === null ? (
                          <span className="text-muted-foreground">—</span>
                        ) : (
                          <>
                            {finding.amount.toLocaleString('en-US', { maximumFractionDigits: 2 })}
                            <span className="block text-xs text-muted-foreground">
                              {finding.unit ?? ''}
                            </span>
                          </>
                        )}
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(finding.createdAt)}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2 lg:items-start">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Actions this console cannot take</CardTitle>
              <CardDescription>
                Shown rather than hidden — the gap is worth knowing about.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-5">
            <UnavailableAction
              label="Mark finding as triaged"
              icon={<CheckCheck />}
              reason="Findings are recomputed from the tables on every scan and are not stored, so there is nowhere to record a triage decision. TODO(server): a findings table with a dismissal reason and an actor, written by a SECURITY DEFINER function."
            />
            <UnavailableAction
              label="Freeze wallet"
              icon={<Snowflake />}
              reason="A negative or mismatched wallet needs the balance held while it is investigated, and no server routine exists to do that. Quarantining the member on the exposure screen is the available containment. TODO(server): a freeze_wallet routine that sets a hold without the client naming an amount."
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Scan coverage</CardTitle>
              <CardDescription>Which tables these findings came from.</CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            {scan.data ? (
              <ScanCoverage
                scannedTables={scan.data.scannedTables}
                scannedRows={scan.data.scannedRows}
                truncatedTables={scan.data.truncatedTables}
                coverage={scan.data.coverage}
                errors={scan.data.errors}
                ranAt={scan.data.ranAt}
              />
            ) : (
              <Skeleton className="h-12 w-full" />
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
