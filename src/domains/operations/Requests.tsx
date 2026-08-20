import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { AlertTriangle, Inbox, MessageSquare, Search, Send } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { relativeTime, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import {
  useBulkUpdateRequests,
  useMessageRequest,
  useRequestHistory,
  useRequestMessages,
  useRequests,
  useUpdateRequest,
} from './hooks';
import {
  GROUP_LABELS,
  SOURCES,
  SOURCE_ORDER,
  isOpen,
  type RequestItem,
  type RequestSource,
} from './requestSources';

type StateFilter = 'open' | 'closed' | 'all';

const STATE_FILTERS: Array<{ id: StateFilter; label: string }> = [
  { id: 'open', label: 'Open' },
  { id: 'closed', label: 'Settled' },
  { id: 'all', label: 'All' },
];

function Chip({
  active,
  children,
  onClick,
}: {
  active: boolean;
  children: React.ReactNode;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
        active
          ? 'bg-primary/10 text-primary ring-primary/20'
          : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
      )}
    >
      {children}
    </button>
  );
}

/* ----------------------------------------------------------- detail pane */

function Thread({ item }: { item: RequestItem }) {
  const messages = useRequestMessages(item.source, item.id);
  const send = useMessageRequest();
  const [body, setBody] = useState('');
  const [requiresResponse, setRequiresResponse] = useState(true);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!body.trim()) return;
    if (!item.userId) {
      toast.error('This request has no member attached, so it cannot be answered.');
      return;
    }
    try {
      await send.mutateAsync({
        source: item.source,
        id: item.id,
        userId: item.userId,
        body: body.trim(),
        requiresResponse,
        subject: `Re: ${SOURCES[item.source].label}`,
      });
      toast.success('Message sent to the member.');
      setBody('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not send the message');
    }
  }

  return (
    <div className="space-y-3">
      <h3 className="flex items-center gap-2 text-sm font-medium">
        <MessageSquare className="size-4 text-muted-foreground" />
        Conversation
      </h3>

      {messages.isLoading ? (
        <Skeleton className="h-16 w-full" />
      ) : messages.isError ? (
        <ErrorState
          title="Could not load the thread"
          error={messages.error}
          onRetry={() => void messages.refetch()}
        />
      ) : (messages.data ?? []).length === 0 ? (
        <p className="text-sm text-muted-foreground">Nothing has been sent to the member yet.</p>
      ) : (
        <ul className="space-y-2">
          {(messages.data ?? []).map((message) => (
            <li key={message.id} className="rounded-md border border-border p-3">
              <div className="mb-1 flex items-center justify-between gap-2">
                <Badge tone={message.sender_role === 'admin' ? 'primary' : 'neutral'}>
                  {message.sender_role}
                </Badge>
                <span className="text-xs text-muted-foreground">{relativeTime(message.created_at)}</span>
              </div>
              <p className="whitespace-pre-wrap text-sm">{message.body}</p>
              {message.requires_response && (
                <p className="mt-1 text-xs text-warning">A reply was requested.</p>
              )}
            </li>
          ))}
        </ul>
      )}

      <form className="space-y-2" onSubmit={submit}>
        <label className="sr-only" htmlFor="request-message">
          Message to the member
        </label>
        <textarea
          id="request-message"
          rows={3}
          value={body}
          maxLength={2000}
          onChange={(e) => setBody(e.target.value)}
          placeholder="Ask the member for what is missing…"
          className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm placeholder:text-muted-foreground"
        />
        <div className="flex flex-wrap items-center gap-3">
          <Button type="submit" size="sm" disabled={!body.trim() || send.isPending}>
            <Send />
            {send.isPending ? 'Sending…' : 'Send to member'}
          </Button>
          <label className="flex items-center gap-2 text-xs text-muted-foreground">
            <input
              type="checkbox"
              className="size-4 rounded border-input accent-primary"
              checked={requiresResponse}
              onChange={(e) => setRequiresResponse(e.target.checked)}
            />
            Mark as an information request
          </label>
        </div>
      </form>
    </div>
  );
}

function DetailPane({ item }: { item: RequestItem }) {
  const update = useUpdateRequest();
  const history = useRequestHistory();
  const [notes, setNotes] = useState('');
  const def = SOURCES[item.source];

  const entries = useMemo(
    () =>
      (history.data ?? []).filter(
        (row) => row.entity_type === item.source && row.entity_id === item.id
      ),
    [history.data, item.source, item.id]
  );

  async function decide(status: string) {
    try {
      await update.mutateAsync({ source: item.source, id: item.id, status, notes });
      toast.success(`Marked ${status.replace(/_/g, ' ')}.`);
      setNotes('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not update the request');
    }
  }

  return (
    <Card>
      <CardHeader>
        <div className="min-w-0 space-y-1">
          <CardTitle className="truncate">{item.title}</CardTitle>
          <CardDescription>
            {def.label} · opened {shortDate(item.createdAt)}
          </CardDescription>
        </div>
        <StatusBadge status={item.status} />
      </CardHeader>

      <CardContent className="space-y-6">
        <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
          {item.details.map((field) => (
            <div key={field.label} className="min-w-0">
              <dt className="text-xs uppercase tracking-wide text-muted-foreground">{field.label}</dt>
              <dd className="break-words text-sm">{field.value}</dd>
            </div>
          ))}
          {item.details.length === 0 && (
            <p className="text-sm text-muted-foreground">This request carries no extra detail.</p>
          )}
        </dl>

        <div className="space-y-2 border-t border-border pt-4">
          <label className="text-sm font-medium" htmlFor="decision-note">
            Decision note
          </label>
          <Input
            id="decision-note"
            value={notes}
            maxLength={500}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Recorded against the decision in the audit log"
          />
          <div className="flex flex-wrap gap-2 pt-1">
            <Button size="sm" disabled={update.isPending} onClick={() => void decide(def.approve)}>
              {def.approve.replace(/_/g, ' ')}
            </Button>
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
            <Button
              size="sm"
              variant="ghost"
              disabled={update.isPending}
              onClick={() => void decide(def.decline)}
            >
              {def.decline.replace(/_/g, ' ')}
            </Button>
          </div>
        </div>

        <div className="border-t border-border pt-4">
          <Thread item={item} />
        </div>

        <div className="space-y-2 border-t border-border pt-4">
          <h3 className="text-sm font-medium">Decision history</h3>
          {history.isLoading ? (
            <Skeleton className="h-12 w-full" />
          ) : entries.length === 0 ? (
            <p className="text-sm text-muted-foreground">No decisions recorded against this request.</p>
          ) : (
            <ul className="space-y-1.5">
              {entries.map((entry) => (
                <li key={entry.id} className="flex flex-wrap items-baseline gap-2 text-sm">
                  <span className="font-medium">{entry.action}</span>
                  <span className="text-muted-foreground">
                    {entry.from_status ?? '—'} → {entry.to_status ?? '—'}
                  </span>
                  <span className="text-xs text-muted-foreground">{relativeTime(entry.created_at)}</span>
                  {entry.notes && <span className="w-full text-xs text-muted-foreground">{entry.notes}</span>}
                </li>
              ))}
            </ul>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

/* ------------------------------------------------------------------- page */

export default function Requests() {
  const requests = useRequests();
  const bulk = useBulkUpdateRequests();

  const [search, setSearch] = useState('');
  const [state, setState] = useState<StateFilter>('open');
  const [source, setSource] = useState<RequestSource | 'all'>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [activeKey, setActiveKey] = useState<string | null>(null);

  const items = useMemo(() => requests.data?.items ?? [], [requests.data]);
  const failures = requests.data?.failures ?? [];

  const shown = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return items.filter((item) => {
      if (source !== 'all' && item.source !== source) return false;
      if (state === 'open' && !isOpen(item)) return false;
      if (state === 'closed' && isOpen(item)) return false;
      if (needle && !item.haystack.includes(needle)) return false;
      return true;
    });
  }, [items, search, state, source]);

  const counts = useMemo(() => {
    const open = items.filter(isOpen);
    const byGroup = (group: keyof typeof GROUP_LABELS) =>
      open.filter((item) => SOURCES[item.source].group === group).length;
    return {
      open: open.length,
      support: byGroup('support'),
      assets: byGroup('assets'),
      compliance: byGroup('compliance'),
    };
  }, [items]);

  const active = useMemo(() => shown.find((item) => item.key === activeKey) ?? null, [shown, activeKey]);

  const picked = useMemo(() => shown.filter((item) => selected.has(item.key)), [shown, selected]);

  function toggle(key: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  /** Group the selection by source so each table gets the status it uses. */
  function batchesFor(kind: 'approve' | 'decline' | 'under_review') {
    const grouped = new Map<RequestSource, string[]>();
    for (const item of picked) {
      const list = grouped.get(item.source) ?? [];
      list.push(item.id);
      grouped.set(item.source, list);
    }
    return [...grouped.entries()].map(([src, ids]) => ({
      source: src,
      ids,
      status:
        kind === 'approve'
          ? SOURCES[src].approve
          : kind === 'decline'
            ? SOURCES[src].decline
            : 'under_review',
    }));
  }

  const canReview = picked.length > 0 && picked.every((i) => SOURCES[i.source].extra.includes('under_review'));

  async function runBulk(kind: 'approve' | 'decline' | 'under_review') {
    try {
      const outcome = await bulk.mutateAsync({ batches: batchesFor(kind) });
      toast.success(
        `${outcome.updated} updated${outcome.failed > 0 ? `, ${outcome.failed} refused` : ''}.`
      );
      setSelected(new Set());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The bulk update failed');
    }
  }

  return (
    <>
      <PageHeader
        title="Request inbox"
        description="Everything a member has asked an administrator to decide, from nine queues, in one place."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Open requests" value={counts.open} loading={requests.isLoading} tone="primary" />
        <Stat label={GROUP_LABELS.support} value={counts.support} loading={requests.isLoading} />
        <Stat label={GROUP_LABELS.assets} value={counts.assets} loading={requests.isLoading} />
        <Stat label={GROUP_LABELS.compliance} value={counts.compliance} loading={requests.isLoading} />
      </div>

      {failures.length > 0 && (
        <Card className="mb-4">
          <CardContent className="flex items-start gap-3 py-4">
            <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" />
            <div className="text-sm">
              <p className="font-medium">These queues could not be read, so the counts are partial.</p>
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
              placeholder="Search requests"
              aria-label="Search requests"
              className="pl-9"
            />
          </div>

          <div className="flex flex-wrap gap-2">
            {STATE_FILTERS.map((filter) => (
              <Chip key={filter.id} active={state === filter.id} onClick={() => setState(filter.id)}>
                {filter.label}
              </Chip>
            ))}
          </div>

          <div className="flex flex-wrap gap-2">
            <Chip active={source === 'all'} onClick={() => setSource('all')}>
              All queues
            </Chip>
            {SOURCE_ORDER.map((key) => (
              <Chip key={key} active={source === key} onClick={() => setSource(key)}>
                {SOURCES[key].label}
              </Chip>
            ))}
          </div>
        </CardContent>
      </Card>

      {picked.length > 0 && (
        <Card className="mb-4">
          <CardContent className="flex flex-wrap items-center gap-2 py-4">
            <span className="text-sm font-medium">{picked.length} selected</span>
            <div className="flex-1" />
            <Button size="sm" disabled={bulk.isPending} onClick={() => void runBulk('approve')}>
              Approve
            </Button>
            <Button
              size="sm"
              variant="secondary"
              disabled={bulk.isPending || !canReview}
              title={canReview ? undefined : 'Not every selected queue supports "under review".'}
              onClick={() => void runBulk('under_review')}
            >
              Under review
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={bulk.isPending}
              onClick={() => void runBulk('decline')}
            >
              Decline
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setSelected(new Set())}>
              Clear
            </Button>
          </CardContent>
        </Card>
      )}

      {requests.isLoading ? (
        <div className="grid gap-4 lg:grid-cols-[minmax(0,22rem)_1fr]">
          <Skeleton className="h-96 w-full" />
          <Skeleton className="h-96 w-full" />
        </div>
      ) : requests.isError ? (
        <Card>
          <ErrorState error={requests.error} onRetry={() => void requests.refetch()} />
        </Card>
      ) : shown.length === 0 ? (
        <Card>
          <EmptyState
            title="Nothing waiting"
            description="No request matches these filters."
            icon={<Inbox className="size-5" />}
          />
        </Card>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[minmax(0,22rem)_1fr] lg:items-start">
          <Card className="max-h-[42rem] overflow-y-auto">
            <ul className="divide-y divide-border">
              {shown.map((item) => (
                <li key={item.key}>
                  <div
                    className={cn(
                      'flex items-start gap-3 p-3 transition-colors',
                      activeKey === item.key ? 'bg-primary/5' : 'hover:bg-elevated/50'
                    )}
                  >
                    <input
                      type="checkbox"
                      className="mt-1 size-4 shrink-0 rounded border-input accent-primary"
                      checked={selected.has(item.key)}
                      onChange={() => toggle(item.key)}
                      aria-label={`Select ${item.title}`}
                    />
                    <button
                      type="button"
                      onClick={() => setActiveKey(item.key)}
                      className="min-w-0 flex-1 text-left"
                    >
                      <p className="truncate text-sm font-medium">{item.title}</p>
                      <p className="truncate text-xs text-muted-foreground">{item.subtitle}</p>
                      <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
                        <Badge tone="neutral">{SOURCES[item.source].label}</Badge>
                        <StatusBadge status={item.status} />
                        <span className="text-xs text-muted-foreground">
                          {relativeTime(item.createdAt)}
                        </span>
                      </div>
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </Card>

          {active ? (
            <DetailPane key={active.key} item={active} />
          ) : (
            <Card>
              <EmptyState
                title="Pick a request"
                description="Choose one from the queue to see its detail and decide it."
                icon={<Inbox className="size-5" />}
              />
            </Card>
          )}
        </div>
      )}
    </>
  );
}
