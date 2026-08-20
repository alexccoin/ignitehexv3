import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { AlertTriangle, LifeBuoy, Search } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { relativeTime } from '@/lib/format';
import { cn } from '@/lib/utils';
import { useSupportTickets, useUpdateRequest, SUPPORT_SOURCES } from './hooks';
import { SOURCES, isOpen, type RequestItem, type RequestSource } from './requestSources';

type QueueFilter = RequestSource | 'all';

const SEVERITY_TONE: Record<string, 'danger' | 'warning' | 'info' | 'neutral'> = {
  critical: 'danger',
  high: 'danger',
  urgent: 'danger',
  medium: 'warning',
  normal: 'info',
  low: 'neutral',
};

function severityOf(item: RequestItem): string | null {
  return (
    item.details.find((d) => d.label === 'Severity' || d.label === 'Priority')?.value.toLowerCase() ??
    null
  );
}

function Ticket({ item }: { item: RequestItem }) {
  const update = useUpdateRequest();
  const [open, setOpen] = useState(false);
  const [notes, setNotes] = useState('');
  const def = SOURCES[item.source];
  const severity = severityOf(item);

  async function decide(status: string) {
    try {
      await update.mutateAsync({ source: item.source, id: item.id, status, notes });
      toast.success(`Ticket marked ${status.replace(/_/g, ' ')}.`);
      setNotes('');
      setOpen(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not update the ticket');
    }
  }

  return (
    <Card>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate font-medium">{item.title}</p>
            <p className="truncate text-sm text-muted-foreground">{item.subtitle}</p>
          </div>
          <div className="flex shrink-0 flex-wrap items-center gap-2">
            {severity && <Badge tone={SEVERITY_TONE[severity] ?? 'neutral'}>{severity}</Badge>}
            <Badge tone="neutral">{def.label}</Badge>
            <StatusBadge status={item.status} />
          </div>
        </div>

        <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-2">
          {item.details
            .filter((d) => d.label !== 'Severity' && d.label !== 'Priority')
            .map((field) => (
              <div key={field.label} className="min-w-0">
                <dt className="text-xs uppercase tracking-wide text-muted-foreground">{field.label}</dt>
                <dd className="break-words text-sm">{field.value}</dd>
              </div>
            ))}
        </dl>

        <div className="flex flex-wrap items-center gap-3">
          <span className="text-xs text-muted-foreground">Opened {relativeTime(item.createdAt)}</span>
          <div className="flex-1" />
          <Button size="sm" variant="secondary" onClick={() => setOpen((prev) => !prev)}>
            {open ? 'Close' : 'Manage ticket'}
          </Button>
        </div>

        {open && (
          <div className="space-y-2 border-t border-border pt-3">
            <label className="text-sm font-medium" htmlFor={`note-${item.key}`}>
              Note for the audit log
            </label>
            <Input
              id={`note-${item.key}`}
              value={notes}
              maxLength={500}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="What was done, and why"
            />
            <div className="flex flex-wrap gap-2 pt-1">
              {def.extra.map((status) => (
                <Button
                  key={status}
                  size="sm"
                  variant="secondary"
                  disabled={update.isPending}
                  onClick={() => void decide(status)}
                >
                  {status.replace(/_/g, ' ')}
                </Button>
              ))}
              <Button size="sm" disabled={update.isPending} onClick={() => void decide(def.approve)}>
                {def.approve}
              </Button>
              <Button
                size="sm"
                variant="ghost"
                disabled={update.isPending}
                onClick={() => void decide(def.decline)}
              >
                {def.decline}
              </Button>
            </div>
            {/* v2 wrote `admin_notes: adminNotes || null`, so opening the editor
                and leaving it blank wiped whatever note was already there. The
                RPC only records a note when one is given. */}
            <p className="text-xs text-muted-foreground">
              Leaving this blank keeps the existing note; it is not overwritten.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

export default function Support() {
  const tickets = useSupportTickets();
  const [queue, setQueue] = useState<QueueFilter>('all');
  const [search, setSearch] = useState('');
  const [openOnly, setOpenOnly] = useState(true);

  const items = useMemo(() => tickets.data?.items ?? [], [tickets.data]);
  const failures = tickets.data?.failures ?? [];

  const shown = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return items.filter((item) => {
      if (queue !== 'all' && item.source !== queue) return false;
      if (openOnly && !isOpen(item)) return false;
      if (needle && !item.haystack.includes(needle)) return false;
      return true;
    });
  }, [items, queue, search, openOnly]);

  const counts = useMemo(() => {
    const open = items.filter(isOpen);
    return {
      open: open.length,
      critical: open.filter((item) => {
        const severity = severityOf(item);
        return severity === 'critical' || severity === 'high' || severity === 'urgent';
      }).length,
      member: open.filter((item) => item.source === 'member_support_tickets').length,
      arx: open.filter((item) => item.source === 'arx_support_tickets').length,
    };
  }, [items]);

  return (
    <>
      <PageHeader
        title="Support"
        description="Member and ARX tickets. Decisions are recorded by the same server function the request inbox uses."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Open tickets" value={counts.open} loading={tickets.isLoading} tone="primary" />
        <Stat
          label="High or critical"
          value={counts.critical}
          loading={tickets.isLoading}
          tone={counts.critical > 0 ? 'danger' : 'default'}
        />
        <Stat label="Member tickets" value={counts.member} loading={tickets.isLoading} />
        <Stat label="ARX tickets" value={counts.arx} loading={tickets.isLoading} />
      </div>

      {failures.length > 0 && (
        <Card className="mb-4">
          <CardContent className="flex items-start gap-3 py-4">
            <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" />
            <div className="text-sm">
              <p className="font-medium">These queues could not be read.</p>
              <ul className="mt-1 space-y-0.5 text-muted-foreground">
                {failures.map((failure) => (
                  <li key={failure.source}>
                    {SOURCES[failure.source].label}: {failure.message}
                  </li>
                ))}
              </ul>
            </div>
          </CardContent>
        </Card>
      )}

      <Card className="mb-4">
        <CardContent className="space-y-3 py-4">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search tickets"
              aria-label="Search tickets"
              className="pl-9"
            />
          </div>
          <div className="flex flex-wrap items-center gap-2">
            {(['all', ...SUPPORT_SOURCES] as QueueFilter[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => setQueue(key)}
                aria-pressed={queue === key}
                className={cn(
                  'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
                  queue === key
                    ? 'bg-primary/10 text-primary ring-primary/20'
                    : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
                )}
              >
                {key === 'all' ? 'All queues' : SOURCES[key].label}
              </button>
            ))}
            <div className="flex-1" />
            <label className="flex items-center gap-2 text-xs text-muted-foreground">
              <input
                type="checkbox"
                className="size-4 rounded border-input accent-primary"
                checked={openOnly}
                onChange={(e) => setOpenOnly(e.target.checked)}
              />
              Open only
            </label>
          </div>
        </CardContent>
      </Card>

      {tickets.isLoading ? (
        <div className="space-y-4">
          <Skeleton className="h-36 w-full" />
          <Skeleton className="h-36 w-full" />
        </div>
      ) : tickets.isError ? (
        <Card>
          <ErrorState error={tickets.error} onRetry={() => void tickets.refetch()} />
        </Card>
      ) : shown.length === 0 ? (
        <Card>
          <EmptyState
            title="No tickets"
            description="Nothing matches these filters."
            icon={<LifeBuoy className="size-5" />}
          />
        </Card>
      ) : (
        <div className="space-y-4">
          {shown.map((item) => (
            <Ticket key={item.key} item={item} />
          ))}
        </div>
      )}
    </>
  );
}
