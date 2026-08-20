import { useMemo, useState } from 'react';
import { AlertTriangle, Download, ScrollText } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { CATEGORY_LABELS, isFiatCode, type ActivityCategory, type ActivityEntry } from './ledger';
import { useActivity } from './hooks';

const today = () => new Date().toISOString().slice(0, 10);
const aYearAgo = () => {
  const d = new Date();
  d.setFullYear(d.getFullYear() - 1);
  return d.toISOString().slice(0, 10);
};

/** Movements a statement must not count: they never settled. */
const VOID_STATUS = /failed|cancelled|canceled|rejected|declined/i;

interface Line {
  asset: string;
  kind: 'digital' | 'fiat';
  entries: number;
  credits: number;
  debits: number;
  net: number;
}

/**
 * The whole ledger, filtered and exportable.
 *
 * This is v2's Activity and Statements screens merged: they read the same rows
 * through the same aggregation and differed only in which controls were on
 * screen, so keeping them apart meant fetching everything twice and letting the
 * two disagree about which statuses counted.
 */
export default function WalletActivity() {
  const activity = useActivity();

  const [category, setCategory] = useState<ActivityCategory | 'all'>('all');
  const [scope, setScope] = useState<'all' | 'digital' | 'fiat'>('all');
  const [from, setFrom] = useState(aYearAgo);
  const [to, setTo] = useState(today);
  const [query, setQuery] = useState('');

  const entries = useMemo(() => activity.data?.entries ?? [], [activity.data]);

  const filtered = useMemo(() => {
    const start = new Date(`${from}T00:00:00`).getTime();
    const end = new Date(`${to}T23:59:59`).getTime();
    const needle = query.trim().toLowerCase();

    return entries.filter((r) => {
      const t = new Date(r.date).getTime();
      if (Number.isNaN(t) || t < start || t > end) return false;
      if (category !== 'all' && r.category !== category) return false;
      const fiat = isFiatCode(r.currency);
      if (scope === 'fiat' && !fiat) return false;
      if (scope === 'digital' && fiat) return false;
      if (needle && !`${r.title} ${r.detail} ${r.currency} ${r.source}`.toLowerCase().includes(needle))
        return false;
      return true;
    });
  }, [entries, from, to, category, scope, query]);

  /** Per-asset balance sheet over the filtered window. */
  const lines = useMemo<Line[]>(() => {
    const map = new Map<string, Line>();
    for (const r of filtered) {
      if (VOID_STATUS.test(r.status)) continue;
      const asset = r.currency.toUpperCase();
      const line =
        map.get(asset) ??
        { asset, kind: isFiatCode(asset) ? 'fiat' : 'digital', entries: 0, credits: 0, debits: 0, net: 0 };
      line.entries += 1;
      if (r.direction === 'in') line.credits += r.amount;
      else if (r.direction === 'out') line.debits += r.amount;
      line.net = line.credits - line.debits;
      map.set(asset, line);
    }
    return [...map.values()].sort((a, b) => b.entries - a.entries);
  }, [filtered]);

  const counts = useMemo(() => {
    const map = new Map<ActivityCategory, number>();
    for (const r of entries) map.set(r.category, (map.get(r.category) ?? 0) + 1);
    return map;
  }, [entries]);

  const downloadCsv = () => {
    const head = [
      'Timestamp (UTC)', 'Event', 'Detail', 'Source', 'Category',
      'Asset', 'Class', 'Direction', 'Amount', 'Status', 'Reference',
    ];
    const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const body = [...filtered]
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
      .map((r) =>
        [
          r.date,
          r.title,
          r.detail,
          r.source,
          CATEGORY_LABELS[r.category],
          r.currency.toUpperCase(),
          isFiatCode(r.currency) ? 'Fiat' : 'Digital asset',
          r.direction,
          // Signed, so a spreadsheet can total the column without knowing the
          // direction convention.
          r.direction === 'out' ? -r.amount : r.amount,
          r.status,
          r.hash ?? '',
        ]
          .map(esc)
          .join(',')
      );
    const totals = lines.map((l) =>
      ['TOTAL', l.asset, l.kind, `credits ${l.credits}`, `debits ${l.debits}`, `net ${l.net}`]
        .map(esc)
        .join(',')
    );
    const csv = [
      [esc(`Statement ${from} to ${to}`)].join(','),
      '',
      head.map(esc).join(','),
      ...body,
      '',
      ...totals,
    ].join('\n');

    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `statement-${scope}-${from}_${to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const totalCredits = lines.reduce((s, l) => s + l.credits, 0);
  const totalDebits = lines.reduce((s, l) => s + l.debits, 0);

  return (
    <>
      <PageHeader
        title="Activity"
        description="Every booked movement across the wallet, transfer, fiat, conversion and staking ledgers."
        actions={
          <Button variant="secondary" size="sm" onClick={downloadCsv} disabled={filtered.length === 0}>
            <Download />
            Export CSV
          </Button>
        }
      />

      {/* A source that could not be read is named, rather than being folded
          into an empty list — v2 returned [] for a denied query, so an
          incomplete statement looked exactly like a complete one. */}
      {(activity.data?.unavailable.length ?? 0) > 0 && (
        <div className="mb-6 flex items-start gap-3 rounded-xl border border-warning/30 bg-warning/10 p-4">
          <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" />
          <div className="space-y-1 text-sm">
            <p className="font-medium text-foreground">This statement is incomplete</p>
            <p className="text-muted-foreground">
              These ledgers could not be read: {activity.data?.unavailable.join(', ')}. Figures below
              exclude them.
            </p>
          </div>
        </div>
      )}

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat label="Entries" value={String(filtered.length)} loading={activity.isLoading} />
        <Stat
          label="Credits"
          value={totalCredits.toLocaleString('en-IE', { maximumFractionDigits: 2 })}
          sub="Across every asset in view"
          tone="success"
          loading={activity.isLoading}
        />
        <Stat
          label="Debits"
          value={totalDebits.toLocaleString('en-IE', { maximumFractionDigits: 2 })}
          sub="Across every asset in view"
          tone="warning"
          loading={activity.isLoading}
        />
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div>
            <CardTitle>Filters</CardTitle>
            <CardDescription>Everything below, and the export, follows these.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4 pt-3">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Field label="From" htmlFor="act-from">
              <Input id="act-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field label="To" htmlFor="act-to">
              <Input id="act-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            </Field>
            <Field label="Search" htmlFor="act-q">
              <Input
                id="act-q"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Asset, counterparty, reference"
              />
            </Field>
            {/* A group of buttons, not a form control, so it carries a group
                label rather than a <label for> pointing at nothing. */}
            <div className="space-y-1.5" role="group" aria-label="Asset class">
              <p className="text-sm font-medium leading-none text-foreground">Asset class</p>
              <div className="flex gap-1">
                {(['all', 'digital', 'fiat'] as const).map((s) => (
                  <Button
                    key={s}
                    size="sm"
                    variant={scope === s ? 'primary' : 'secondary'}
                    className="flex-1 capitalize"
                    aria-pressed={scope === s}
                    onClick={() => setScope(s)}
                  >
                    {s}
                  </Button>
                ))}
              </div>
            </div>
          </div>

          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => setCategory('all')}
              className={cn(
                'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
                category === 'all'
                  ? 'bg-primary/10 text-primary ring-primary/20'
                  : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
              )}
            >
              All · {entries.length}
            </button>
            {(Object.keys(CATEGORY_LABELS) as ActivityCategory[])
              .filter((c) => (counts.get(c) ?? 0) > 0)
              .map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setCategory(c)}
                  className={cn(
                    'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
                    category === c
                      ? 'bg-primary/10 text-primary ring-primary/20'
                      : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
                  )}
                >
                  {CATEGORY_LABELS[c]} · {counts.get(c)}
                </button>
              ))}
          </div>
        </CardContent>
      </Card>

      {lines.length > 0 && (
        <Card className="mb-6">
          <CardHeader>
            <div>
              <CardTitle>Statement summary</CardTitle>
              <CardDescription>
                Per asset, over the selected period. Conversions are excluded from credits and debits
                because they neither add to nor remove from the portfolio.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="pt-3">
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Asset</TH>
                    <TH>Class</TH>
                    <TH className="text-right">Entries</TH>
                    <TH className="text-right">Credits</TH>
                    <TH className="text-right">Debits</TH>
                    <TH className="text-right">Net</TH>
                  </TR>
                </THead>
                <TBody>
                  {lines.map((l) => (
                    <TR key={l.asset}>
                      <TD className="font-medium">{l.asset}</TD>
                      <TD className="capitalize text-muted-foreground">{l.kind}</TD>
                      <TD className="tabular text-right">{l.entries}</TD>
                      <TD className="tabular text-right text-success">
                        {l.credits.toLocaleString('en-IE', { maximumFractionDigits: 4 })}
                      </TD>
                      <TD className="tabular text-right text-warning">
                        {l.debits.toLocaleString('en-IE', { maximumFractionDigits: 4 })}
                      </TD>
                      <TD
                        className={cn(
                          'tabular text-right font-medium',
                          l.net < 0 ? 'text-danger' : 'text-foreground'
                        )}
                      >
                        {l.net.toLocaleString('en-IE', { maximumFractionDigits: 4 })}
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Entries</CardTitle>
            <CardDescription>Most recent first.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="pt-3">
          {activity.isLoading ? (
            <div className="space-y-2">
              {Array.from({ length: 6 }, (_, i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          ) : activity.isError ? (
            <ErrorState
              title="Could not load your activity"
              error={activity.error}
              onRetry={() => void activity.refetch()}
            />
          ) : filtered.length === 0 ? (
            <EmptyState
              icon={<ScrollText className="size-5" />}
              title={entries.length === 0 ? 'Nothing booked yet' : 'Nothing matches these filters'}
              description={
                entries.length === 0
                  ? 'Movements appear here as soon as the first one settles.'
                  : 'Widen the date range or clear the search to see more.'
              }
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Date</TH>
                    <TH>Event</TH>
                    <TH>Ledger</TH>
                    <TH className="text-right">Amount</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {filtered.slice(0, 250).map((r) => (
                    <ActivityRow key={r.id} entry={r} />
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
          {filtered.length > 250 && (
            <p className="pt-4 text-center text-xs text-muted-foreground">
              Showing the 250 most recent of {filtered.length}. Export the CSV for the full set.
            </p>
          )}
        </CardContent>
      </Card>
    </>
  );
}

function ActivityRow({ entry }: { entry: ActivityEntry }) {
  const sign = entry.direction === 'in' ? '+' : entry.direction === 'out' ? '−' : '';
  const tone =
    entry.direction === 'in' ? 'text-success' : entry.direction === 'out' ? 'text-foreground' : 'text-muted-foreground';

  return (
    <TR>
      <TD className="whitespace-nowrap text-muted-foreground">{shortDate(entry.date)}</TD>
      <TD>
        <p className="font-medium">{entry.title}</p>
        <p className="max-w-md truncate text-xs text-muted-foreground">{entry.detail}</p>
      </TD>
      <TD>
        <Badge tone="neutral">{CATEGORY_LABELS[entry.category]}</Badge>
      </TD>
      <TD className={cn('tabular whitespace-nowrap text-right font-medium', tone)}>
        {sign}
        {entry.amount.toLocaleString('en-IE', { maximumFractionDigits: 6 })} {entry.currency}
      </TD>
      <TD>
        <StatusBadge status={entry.status} />
      </TD>
    </TR>
  );
}
