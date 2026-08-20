import { useMemo, useState } from 'react';
import { ArrowUpRight, FlaskConical, GitCompareArrows, Layers } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import {
  useEcosystem,
  useEcosystemTokens,
  useChainStatus,
  type ComponentStatus,
  type EcosystemComponent,
} from './hooks';

/**
 * The SourceLess ecosystem map.
 *
 * Every card is a row from the database, and every row carries the page of the
 * published overview it came from. Nothing on this screen is written into the
 * component, so the page cannot drift from the document the way a hand-written
 * marketing page does.
 *
 * Two decisions worth stating, because both cost something:
 *
 *  1. **"Not stated" is shown, not hidden.** Most components in the overview
 *     carry no status at all. Rendering them as "live" would be the easy lie;
 *     rendering them as unstated is the honest one, and it makes visible how
 *     much of the ecosystem has no declared maturity.
 *
 *  2. **The chain panel reports THIS deployment, not the document.** The
 *     overview shows a live explorer with 14M+ blocks. This platform has the
 *     chain disabled and its RPC does not resolve. The panel says what is true
 *     here and points at the discrepancy rather than repeating the brochure.
 */

const STATUS_LABEL: Record<ComponentStatus, string> = {
  live: 'Live',
  beta: 'Beta',
  testing: 'Testing',
  rnd: 'R&D',
  planned: 'Planned',
  unstated: 'Not stated',
};

const STATUS_TONE: Record<ComponentStatus, 'success' | 'warning' | 'info' | 'neutral'> = {
  live: 'success',
  beta: 'warning',
  testing: 'warning',
  rnd: 'info',
  planned: 'info',
  unstated: 'neutral',
};

const FILTERS: (ComponentStatus | 'all')[] = ['all', 'live', 'beta', 'testing', 'rnd', 'planned', 'unstated'];

function ComponentCard({ c }: { c: EcosystemComponent }) {
  const status = (c.status ?? 'unstated') as ComponentStatus;
  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="flex-1 space-y-2">
        <div className="flex items-start justify-between gap-2">
          <CardTitle className="text-base leading-snug">{c.name}</CardTitle>
          <Badge tone={STATUS_TONE[status]}>{STATUS_LABEL[status]}</Badge>
        </div>
        <CardDescription>{c.summary}</CardDescription>
        {/* The caveat the overview itself attaches, kept next to the claim it
            qualifies rather than collected in a footnote nobody reads. */}
        {c.status_note && (
          <p className="rounded-md border border-dashed border-border px-2.5 py-1.5 text-xs text-muted-foreground">
            {c.status_note}
          </p>
        )}
      </CardHeader>
      <CardContent className="flex items-center justify-between gap-2 pt-0">
        <span className="font-mono text-xs text-muted-foreground">overview p.{c.source_page}</span>
        {c.url && (
          <Button variant="ghost" size="sm" asChild>
            <a href={c.url} target="_blank" rel="noopener noreferrer">
              Visit
              <ArrowUpRight className="size-3.5" />
            </a>
          </Button>
        )}
      </CardContent>
    </Card>
  );
}

function ChainPanel() {
  const { data: chain, isLoading } = useChainStatus();
  if (isLoading) return <Skeleton className="h-28 w-full" />;

  const enabled = !!chain?.enabled;
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Layers className="size-4 text-muted-foreground" />
          Chain status on this deployment
        </CardTitle>
        <CardDescription>
          What this platform can verify, not what the overview asserts.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
          <span>
            <span className="text-muted-foreground">Chain</span>{' '}
            <span className="font-medium">{chain?.name ?? 'none configured'}</span>
          </span>
          {chain?.chain_id != null && (
            <span className="font-mono text-xs text-muted-foreground">id {chain.chain_id}</span>
          )}
          <Badge tone={enabled ? 'success' : 'danger'}>{enabled ? 'Anchoring enabled' : 'Anchoring disabled'}</Badge>
        </div>
        {chain?.rpc_url && (
          <p className="font-mono text-xs text-muted-foreground">{chain.rpc_url}</p>
        )}
        <p className="text-xs text-muted-foreground">
          The overview shows a block explorer reporting 14M+ blocks at a 0.4s block time (p.114).
          Those figures come from a product screenshot rather than a specification slide, and this
          deployment cannot confirm them — see the reconciliation tab.
        </p>
      </CardContent>
    </Card>
  );
}

function TokenPanel() {
  const { data, isLoading, error } = useEcosystemTokens();
  if (isLoading) return <Skeleton className="h-64 w-full" />;
  if (error) return <ErrorState error={error} />;

  const tokens = data ?? [];
  const named = tokens.filter((t) => t.in_overview);
  const extra = tokens.filter((t) => !t.in_overview);

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        {named.map((t) => (
          <Card key={t.symbol}>
            <CardHeader className="space-y-1.5">
              <div className="flex items-center justify-between gap-2">
                <CardTitle className="font-mono text-base">{t.symbol}</CardTitle>
                <span className="text-xs text-muted-foreground">overview p.{t.source_page}</span>
              </div>
              <CardDescription className="text-foreground">{t.name}</CardDescription>
              <CardDescription>{t.role}</CardDescription>
            </CardHeader>
          </Card>
        ))}
      </div>

      {extra.length > 0 && (
        <Card className="border-warning/30 bg-warning/5">
          <CardHeader>
            <CardTitle className="text-base">
              {extra.length} ledger {extra.length === 1 ? 'asset' : 'assets'} the overview does not name
            </CardTitle>
            <CardDescription>
              This platform's ledger carries {tokens.length} assets. The published overview names{' '}
              {named.length}. The following appear nowhere in its 127 pages, not even in its contents —
              so they are either internal instruments the overview does not cover, or they have no
              counterpart in the published model.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            {extra.map((t) => (
              <Badge key={t.symbol} tone="warning" className="font-mono">
                {t.symbol}
              </Badge>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

export default function EcosystemOverview() {
  const { data, isLoading, error } = useEcosystem();
  const [filter, setFilter] = useState<ComponentStatus | 'all'>('all');

  const bySection = useMemo(() => {
    const map = new Map<string, EcosystemComponent[]>();
    for (const c of data?.components ?? []) {
      if (filter !== 'all' && c.status !== filter) continue;
      const list = map.get(c.section_id) ?? [];
      list.push(c);
      map.set(c.section_id, list);
    }
    return map;
  }, [data, filter]);

  if (isLoading) return <Skeleton className="h-96 w-full" />;
  if (error) return <ErrorState error={error} />;

  const sections = data?.sections ?? [];
  const total = data?.components.length ?? 0;

  return (
    <>
      <PageHeader
        title="SourceLess ecosystem"
        description="Every component below is drawn from the published Technology Overview, with the page it came from."
        actions={
          <Badge tone="warning" className="gap-1.5">
            <FlaskConical className="size-3.5" />
            Beta
          </Badge>
        }
      />

      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        <ChainPanel />
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <GitCompareArrows className="size-4 text-muted-foreground" />
              Reconciliation, not marketing
            </CardTitle>
            <CardDescription>
              The overview contradicts itself in places and contradicts this database in others. Those
              conflicts are recorded and shown rather than resolved, because picking a winner would
              mean inventing authority the document does not give.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button variant="ghost" size="sm" asChild>
              <a href="/ecosystem/reconciliation">
                Open the reconciliation list
                <ArrowUpRight className="size-3.5" />
              </a>
            </Button>
          </CardContent>
        </Card>
      </div>

      <TokenPanel />

      <div className="my-6 flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <Button
            key={f}
            size="sm"
            variant={filter === f ? 'primary' : 'ghost'}
            onClick={() => setFilter(f)}
          >
            {f === 'all' ? `All ${total}` : STATUS_LABEL[f]}
          </Button>
        ))}
      </div>

      <div className="space-y-8">
        {sections.map((s) => {
          const items = bySection.get(s.id) ?? [];
          if (items.length === 0) return null;
          return (
            <section key={s.id}>
              <div className="mb-3">
                <h2 className="text-lg font-semibold tracking-tight">{s.title}</h2>
                {s.subtitle && <p className="text-sm text-muted-foreground">{s.subtitle}</p>}
              </div>
              <div className={cn('grid gap-3', 'sm:grid-cols-2 lg:grid-cols-3')}>
                {items.map((c) => (
                  <ComponentCard key={c.id} c={c} />
                ))}
              </div>
            </section>
          );
        })}
      </div>
    </>
  );
}
