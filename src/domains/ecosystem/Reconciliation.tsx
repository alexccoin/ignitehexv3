import { useState } from 'react';
import { AlertTriangle, FileQuestion, GitCompareArrows } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { useDiscrepancies, type Discrepancy } from './hooks';

/**
 * Where the published overview and this platform disagree.
 *
 * This screen exists because the alternative is worse. The overview is a
 * 127-page marketing document that contradicts itself on release dates, on how
 * many chains the bridge supports, on which tokens are stakeable, and on
 * whether a hardware device is shipping. It also asserts regulatory compliance
 * without naming a regulator, and carries no investment-risk disclaimer at all.
 *
 * A page that rendered only the agreeable parts would be a nicer page and a
 * dishonest one. This platform already has fifteen disagreeing sources for its
 * APY schedule; the cost of quietly picking a winner is exactly that situation,
 * repeated.
 *
 * So each conflict is a row, with both sides quoted and the pages cited, and a
 * reader can go and check. Nothing here is resolved, because resolving it is a
 * decision for whoever owns the document — not for the screen displaying it.
 */

const KIND_LABEL: Record<string, string> = {
  internal: 'Overview contradicts itself',
  platform: 'Overview contradicts this platform',
  unstated: 'Asserted without a basis',
};

const KIND_ICON: Record<string, typeof AlertTriangle> = {
  internal: GitCompareArrows,
  platform: AlertTriangle,
  unstated: FileQuestion,
};

const FILTERS = ['all', 'material', 'internal', 'platform', 'unstated'] as const;
type Filter = (typeof FILTERS)[number];

const FILTER_LABEL: Record<Filter, string> = {
  all: 'All',
  material: 'Material only',
  internal: 'Self-contradictions',
  platform: 'Versus this platform',
  unstated: 'Unsupported claims',
};

function Row({ d }: { d: Discrepancy }) {
  const Icon = KIND_ICON[d.kind] ?? AlertTriangle;
  const material = d.severity === 'material';

  return (
    <Card className={material ? 'border-warning/30' : undefined}>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <CardTitle className="flex items-center gap-2 text-base leading-snug">
            <Icon className={material ? 'size-4 shrink-0 text-warning' : 'size-4 shrink-0 text-muted-foreground'} />
            {d.subject}
          </CardTitle>
          <div className="flex items-center gap-2">
            {material && <Badge tone="warning">Material</Badge>}
            <Badge tone="neutral">{KIND_LABEL[d.kind] ?? d.kind}</Badge>
          </div>
        </div>
        <CardDescription className="font-mono text-xs">{d.source_page}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* Both sides quoted side by side. A summary of a contradiction is not a
            contradiction — the reader needs the two statements to compare. */}
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="rounded-lg border border-border bg-elevated p-3">
            <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              One side
            </p>
            <p className="text-sm">{d.says_a}</p>
          </div>
          <div className="rounded-lg border border-border bg-elevated p-3">
            <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              The other
            </p>
            <p className="text-sm">{d.says_b}</p>
          </div>
        </div>
        {d.note && <p className="text-sm text-muted-foreground">{d.note}</p>}
      </CardContent>
    </Card>
  );
}

export default function Reconciliation() {
  const { data, isLoading, error } = useDiscrepancies();
  const [filter, setFilter] = useState<Filter>('all');

  if (isLoading) return <Skeleton className="h-96 w-full" />;
  if (error) return <ErrorState error={error} />;

  const all = data ?? [];
  const shown = all.filter((d) =>
    filter === 'all' ? true : filter === 'material' ? d.severity === 'material' : d.kind === filter
  );
  const material = all.filter((d) => d.severity === 'material').length;

  return (
    <>
      <PageHeader
        title="Reconciliation"
        description={`${all.length} points where the published overview disagrees with itself or with this platform. ${material} are material.`}
      />

      <Card className="mb-6">
        <CardContent className="space-y-2 pt-5 text-sm text-muted-foreground">
          <p>
            None of these are resolved here. Both sides are quoted with their page numbers so they can
            be checked against the source, and the decision about which is correct belongs to whoever
            owns the document.
          </p>
          <p>
            Two absences are worth naming on their own, because they are not contradictions but gaps:
            the overview describes banking, IBANs, cards, staking yields and investment products across
            127 pages while mentioning <strong>no regulator, licence, MiCA, KYC or audit</strong>, and it
            carries <strong>no investment-risk or forward-looking-statement disclaimer</strong>.
          </p>
        </CardContent>
      </Card>

      <div className="mb-4 flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <Button key={f} size="sm" variant={filter === f ? 'primary' : 'ghost'} onClick={() => setFilter(f)}>
            {FILTER_LABEL[f]}
          </Button>
        ))}
      </div>

      {shown.length === 0 ? (
        <EmptyState title="Nothing in this category" description="Try another filter." />
      ) : (
        <div className="space-y-3">
          {shown.map((d) => (
            <Row key={d.id} d={d} />
          ))}
        </div>
      )}
    </>
  );
}
