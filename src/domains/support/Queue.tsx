import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { toast } from 'sonner';
import { AlertTriangle, Inbox, LifeBuoy, Search, Send, UserPlus } from 'lucide-react';
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
import { SOURCES, isOpen, type RequestItem, type RequestSource } from '@/domains/operations/requestSources';
import {
  sk,
  useQueueDecision,
  useQueueReply,
  useSupportQueue,
  useTicketThread,
  QUEUE_STATUSES,
  SUPPORT_SOURCES,
} from './hooks';
import {
  ASSIGN_UNAVAILABLE,
  Detail,
  LockedAction,
  Section,
  SELECT_CLASS,
  SeverityBadge,
  TEXTAREA_CLASS,
  Thread,
} from './shared';

/**
 * Staff triage.
 *
 * This is the richer half of the pair. `operations/support` is the decision
 * list: every open ticket, a status, a note, done. What it cannot do is hold a
 * conversation — an administrator who needed to ask the member a question had
 * to leave for the request inbox, find the same row under a different heading
 * and message it from there. Here the queue and the thread are one screen: pick
 * a ticket on the left, read what the member said and what has been said back,
 * reply, and set the status without losing your place.
 *
 * It reads through the operations loader and writes through the same two RPCs
 * (`v2_admin_update_request`, `v2_admin_message_request`), so there is one set
 * of columns and one audit trail. Nothing here talks to the ticket tables
 * directly. See the note at the top of ./hooks.ts.
 */

type SourceFilter = RequestSource | 'all';
type StatusFilter = string | 'all';

const SEVERITY_LABELS = ['Severity', 'Priority'];

/** Member tickets record a Severity; ARX tickets record a Priority. */
function severityOf(item: RequestItem): string | null {
  return item.details.find((d) => SEVERITY_LABELS.includes(d.label))?.value.toLowerCase() ?? null;
}

function isUrgent(item: RequestItem): boolean {
  const severity = severityOf(item);
  return severity === 'critical' || severity === 'high' || severity === 'urgent';
}

/**
 * A row in the queue list.
 *
 * Deliberately compact: the point of the list is choosing what to work on, and
 * a wall of full ticket bodies makes that harder rather than easier. The detail
 * pane carries everything.
 */
function QueueRow({
  item,
  selected,
  onSelect,
}: {
  item: RequestItem;
  selected: boolean;
  onSelect: () => void;
}) {
  const severity = severityOf(item);
  return (
    <li>
      <button
        type="button"
        onClick={onSelect}
        aria-current={selected ? 'true' : undefined}
        className={cn(
          'w-full rounded-lg border p-3 text-left transition-colors',
          selected
            ? 'border-primary/40 bg-primary/5'
            : 'border-border hover:bg-elevated'
        )}
      >
        <div className="flex items-start justify-between gap-2">
          <p className="min-w-0 truncate text-sm font-medium">{item.title}</p>
          {severity && <SeverityBadge severity={severity} />}
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{item.subtitle}</p>
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <StatusBadge status={item.status} />
          <span className="text-xs text-muted-foreground">{relativeTime(item.createdAt)}</span>
        </div>
      </button>
    </li>
  );
}

/**
 * The selected ticket: what it says, the conversation, and the two things staff
 * can actually do to it.
 */
function TicketPane({ item }: { item: RequestItem }) {
  const qc = useQueryClient();
  const thread = useTicketThread(item.source, item.id);
  const decide = useQueueDecision();
  const reply = useQueueReply();

  const [body, setBody] = useState('');
  const [requiresResponse, setRequiresResponse] = useState(false);
  const [note, setNote] = useState('');
  const [status, setStatus] = useState(item.status);

  // Switching ticket must not carry the previous ticket's half-written reply
  // into the new one — sending the wrong member somebody else's message is not
  // a mistake worth risking for the sake of a persisted draft.
  useEffect(() => {
    setBody('');
    setRequiresResponse(false);
    setNote('');
    setStatus(item.status);
  }, [item.key, item.status]);

  const statuses = QUEUE_STATUSES[item.source] ?? [item.status];

  /**
   * ARX tickets cannot be replied to from here, and this is not a UI decision.
   *
   * `v2_admin_message_request` takes `p_user_id` and delivers the message to
   * that user. For a member ticket that is `member_support_tickets.user_id`, an
   * auth user id, and the loader carries it through correctly. For an ARX
   * ticket the loader carries `arx_support_tickets.submitted_by`, and the only
   * policy on that table compares `submitted_by` to `arx_club_members.id` — a
   * club-membership row id, not a user id. Sending it as `p_user_id` would post
   * the ticket's contents to whichever account happens to own that uuid, or to
   * nobody. Either outcome is worse than the button being off.
   */
  const canReply = item.source === 'member_support_tickets';

  async function sendReply(event: FormEvent) {
    event.preventDefault();
    if (!canReply || !body.trim()) return;
    try {
      await reply.mutateAsync({
        source: item.source,
        id: item.id,
        userId: item.userId,
        body: body.trim(),
        requiresResponse,
      });
      // The reply RPC invalidates the operations keys; the thread lives under
      // this domain's keys, so it has to be told separately or the message the
      // administrator just sent does not appear until the next refetch.
      void qc.invalidateQueries({ queryKey: sk.thread(item.source, item.id) });
      toast.success('Sent to the member.');
      setBody('');
      setRequiresResponse(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The message was not sent.');
    }
  }

  async function applyStatus() {
    if (status === item.status && !note.trim()) return;
    try {
      await decide.mutateAsync({
        source: item.source,
        id: item.id,
        status,
        notes: note,
      });
      toast.success(`Ticket set to ${status.replace(/_/g, ' ')}.`);
      setNote('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The ticket was not updated.');
    }
  }

  return (
    <div className="space-y-6">
      <Section
        title={item.title}
        description={item.subtitle}
        actions={
          <div className="flex shrink-0 flex-wrap items-center gap-2">
            <Badge tone="neutral">{SOURCES[item.source].label}</Badge>
            <StatusBadge status={item.status} />
          </div>
        }
      >
        <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
          {item.details.map((field) => (
            <Detail key={field.label} label={field.label} value={field.value} />
          ))}
          <Detail label="Opened" value={relativeTime(item.createdAt)} />
        </dl>
      </Section>

      <Section
        title="Conversation"
        description="Messages exchanged with the member. Internal notes below are not shown to them."
      >
        <Thread
          query={thread}
          perspective="staff"
          emptyDescription="Nothing has been said to the member about this ticket yet."
        />

        <form className="mt-5 space-y-2 border-t border-border pt-4" onSubmit={(e) => void sendReply(e)}>
          <label className="text-sm font-medium" htmlFor="queue-reply">
            Reply to the member
          </label>
          <textarea
            id="queue-reply"
            rows={3}
            maxLength={2000}
            className={TEXTAREA_CLASS}
            value={body}
            disabled={!canReply}
            onChange={(e) => setBody(e.target.value)}
            placeholder={
              canReply
                ? 'What you have done, or what you need from them.'
                : 'Replying to ARX tickets is not available from here.'
            }
          />
          {canReply ? (
            <div className="flex flex-wrap items-center gap-3">
              <Button type="submit" size="sm" disabled={!body.trim() || reply.isPending}>
                <Send aria-hidden="true" />
                {reply.isPending ? 'Sending…' : 'Send to member'}
              </Button>
              <label className="flex items-center gap-2 text-xs text-muted-foreground">
                <input
                  type="checkbox"
                  className="size-4 rounded border-input accent-primary"
                  checked={requiresResponse}
                  onChange={(e) => setRequiresResponse(e.target.checked)}
                />
                Mark as needing a reply from them
              </label>
            </div>
          ) : (
            <p className="flex max-w-prose items-start gap-1.5 text-xs text-muted-foreground">
              <AlertTriangle className="mt-0.5 size-3 shrink-0" aria-hidden="true" />
              v2_admin_message_request delivers to the user id it is given, and an ARX ticket
              carries a club-membership id in that field rather than a user id. Sending would
              post this ticket to whichever account owns that uuid. TODO(server): resolve the
              recipient inside the RPC from arx_club_members.user_id when the source is
              arx_support_tickets.
            </p>
          )}
        </form>
      </Section>

      <Section title="Triage" description="Recorded by the same server function the request inbox uses.">
        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="queue-status">
                Status
              </label>
              <select
                id="queue-status"
                className={SELECT_CLASS}
                value={status}
                onChange={(e) => setStatus(e.target.value)}
              >
                {/* The current status is offered even when it is outside the
                    list, so a row already holding an unexpected value can be
                    seen rather than silently rewritten by the select. */}
                {(statuses.includes(item.status) ? statuses : [item.status, ...statuses]).map(
                  (value) => (
                    <option key={value} value={value}>
                      {value.replace(/_/g, ' ')}
                    </option>
                  )
                )}
              </select>
            </div>

            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="queue-note">
                Note for the audit log
              </label>
              <Input
                id="queue-note"
                value={note}
                maxLength={500}
                onChange={(e) => setNote(e.target.value)}
                placeholder="What was done, and why"
              />
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <Button
              size="sm"
              disabled={decide.isPending || (status === item.status && !note.trim())}
              onClick={() => void applyStatus()}
            >
              {decide.isPending ? 'Saving…' : 'Apply'}
            </Button>
            <p className="text-xs text-muted-foreground">
              Leaving the note blank keeps whatever note is already on the ticket; it is not
              overwritten.
            </p>
          </div>

          <div className="border-t border-border pt-4">
            <LockedAction
              label="Assign to someone"
              reason={ASSIGN_UNAVAILABLE}
              icon={<UserPlus aria-hidden="true" />}
            />
          </div>
        </div>
      </Section>
    </div>
  );
}

export default function Queue() {
  const queue = useSupportQueue();
  const [source, setSource] = useState<SourceFilter>('all');
  const [status, setStatus] = useState<StatusFilter>('open');
  const [search, setSearch] = useState('');
  const [selectedKey, setSelectedKey] = useState<string | null>(null);

  const items = useMemo(() => queue.data?.items ?? [], [queue.data]);
  const failures = queue.data?.failures ?? [];

  /** Every status actually present, so the filter reflects the data not a guess. */
  const statusOptions = useMemo(() => {
    const seen = new Set(items.map((item) => item.status.toLowerCase()));
    return [...seen].sort();
  }, [items]);

  const shown = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return items.filter((item) => {
      if (source !== 'all' && item.source !== source) return false;
      if (status === 'open' && !isOpen(item)) return false;
      if (status !== 'all' && status !== 'open' && item.status.toLowerCase() !== status) return false;
      if (needle && !item.haystack.includes(needle)) return false;
      return true;
    });
  }, [items, source, status, search]);

  // Keep a selection that is still on screen. Without this, filtering away the
  // open ticket leaves the detail pane showing something the list no longer
  // contains, which is how an administrator ends up resolving the wrong row.
  const selected = shown.find((item) => item.key === selectedKey) ?? null;
  useEffect(() => {
    if (selectedKey && !shown.some((item) => item.key === selectedKey)) setSelectedKey(null);
  }, [shown, selectedKey]);

  const counts = useMemo(() => {
    const open = items.filter(isOpen);
    return {
      open: open.length,
      urgent: open.filter(isUrgent).length,
      member: open.filter((item) => item.source === 'member_support_tickets').length,
      arx: open.filter((item) => item.source === 'arx_support_tickets').length,
    };
  }, [items]);

  return (
    <>
      <PageHeader
        title="Support queue"
        description="Triage with the conversation attached. Decisions and messages go through the same server functions as the request inbox."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Open" value={counts.open} loading={queue.isLoading} tone="primary" />
        <Stat
          label="High or critical"
          value={counts.urgent}
          loading={queue.isLoading}
          tone={counts.urgent > 0 ? 'danger' : 'default'}
        />
        <Stat label="Member tickets" value={counts.member} loading={queue.isLoading} />
        <Stat label="ARX tickets" value={counts.arx} loading={queue.isLoading} />
      </div>

      {failures.length > 0 && (
        <Card className="mb-4">
          <CardContent className="flex items-start gap-3 py-4">
            <AlertTriangle className="mt-0.5 size-4 shrink-0 text-warning" aria-hidden="true" />
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

      <Card className="mb-6">
        <CardContent className="space-y-3 py-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="relative">
              <Search
                className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden="true"
              />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search tickets"
                aria-label="Search tickets"
                className="pl-9"
              />
            </div>
            <div>
              <label className="sr-only" htmlFor="queue-status-filter">
                Filter by status
              </label>
              <select
                id="queue-status-filter"
                className={SELECT_CLASS}
                value={status}
                onChange={(e) => setStatus(e.target.value)}
              >
                <option value="open">Open — anything still needing attention</option>
                <option value="all">Any status</option>
                {statusOptions.map((value) => (
                  <option key={value} value={value}>
                    {value.replace(/_/g, ' ')}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {(['all', ...SUPPORT_SOURCES] as SourceFilter[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => setSource(key)}
                aria-pressed={source === key}
                className={cn(
                  'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
                  source === key
                    ? 'bg-primary/10 text-primary ring-primary/20'
                    : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
                )}
              >
                {key === 'all' ? 'Both queues' : SOURCES[key].label}
              </button>
            ))}
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <Section title={`Queue${shown.length ? ` · ${shown.length}` : ''}`}>
            {queue.isLoading ? (
              <div className="space-y-3">
                <Skeleton className="h-20 w-full" />
                <Skeleton className="h-20 w-full" />
                <Skeleton className="h-20 w-full" />
              </div>
            ) : queue.isError ? (
              <ErrorState error={queue.error} onRetry={() => void queue.refetch()} />
            ) : shown.length === 0 ? (
              <EmptyState
                title="Nothing here"
                description={
                  source === 'arx_support_tickets'
                    ? 'No ARX tickets came back. The only policy on arx_support_tickets scopes rows to the submitting club member, so an administrator who is not one reads an empty table rather than an error.'
                    : 'Nothing matches these filters.'
                }
                icon={<Inbox className="size-5" />}
              />
            ) : (
              <ul className="max-h-[70vh] space-y-2 overflow-y-auto pr-1">
                {shown.map((item) => (
                  <QueueRow
                    key={item.key}
                    item={item}
                    selected={item.key === selectedKey}
                    onSelect={() => setSelectedKey(item.key)}
                  />
                ))}
              </ul>
            )}
          </Section>
        </div>

        <div className="lg:col-span-3">
          {selected ? (
            <TicketPane key={selected.key} item={selected} />
          ) : (
            <Card>
              <EmptyState
                title="Pick a ticket"
                description="Choose one from the queue to read what the member said, reply, and set its status."
                icon={<LifeBuoy className="size-5" />}
              />
            </Card>
          )}
        </div>
      </div>
    </>
  );
}
