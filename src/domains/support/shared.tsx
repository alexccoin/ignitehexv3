import type { ReactNode } from 'react';
import { AlertTriangle, Lock, MessageSquare } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { relativeTime } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { ThreadMessage } from './hooks';

/**
 * The pieces the four support screens share.
 *
 * They live together so that the conversation renders identically on the member
 * side and the staff side — one component, one set of columns, one decision
 * about what a message is allowed to show. v2 had the member's view of a ticket
 * and the admin's view of the same ticket written twice, and only one of them
 * hid the internal notes.
 */

/* ---------------------------------------------------------------- labels */

/** The category values the CHECK constraint allows, in human words. */
export const CATEGORY_LABELS: Record<string, string> = {
  profile_security: 'Profile and security',
  voucher: 'Vouchers',
  staking: 'Staking',
  banking: 'Banking',
  other: 'Something else',
};

export function categoryLabel(value: string | null | undefined): string {
  if (!value) return 'Uncategorised';
  return CATEGORY_LABELS[value] ?? value.replace(/_/g, ' ');
}

const SEVERITY_TONE: Record<string, 'danger' | 'warning' | 'info' | 'neutral'> = {
  critical: 'danger',
  urgent: 'danger',
  high: 'warning',
  medium: 'info',
  normal: 'info',
  low: 'neutral',
};

/**
 * Severity as a word and a colour.
 *
 * The word is always present. A red badge and an amber badge are the same badge
 * in greyscale, in forced-colors mode, and to a red-blind reader.
 */
export function SeverityBadge({ severity }: { severity: string | null | undefined }) {
  const key = (severity ?? 'medium').toLowerCase();
  return <Badge tone={SEVERITY_TONE[key] ?? 'neutral'}>{key}</Badge>;
}

/** Statuses that mean the ticket is still someone's problem. */
export const OPEN_TICKET_STATUSES = ['pending', 'open', 'in_progress', 'escalated', 'new'];

export function isTicketOpen(status: string | null | undefined): boolean {
  return OPEN_TICKET_STATUSES.includes((status ?? '').toLowerCase());
}

/* --------------------------------------------------------------- layout */

/** A titled panel, so section headings stay identical across the domain. */
export function Section({
  title,
  description,
  actions,
  children,
  className,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <Card className={className}>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle>{title}</CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </div>
        {actions}
      </CardHeader>
      <CardContent className="pt-4">{children}</CardContent>
    </Card>
  );
}

/** A short label/value pair for detail panels. */
export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="min-w-0 space-y-0.5">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="break-words text-sm">{value}</p>
    </div>
  );
}

/* ------------------------------------------------------- locked controls */

/**
 * A control the browser is not allowed to operate.
 *
 * Rendered disabled with the reason beside it rather than omitted, because the
 * gap is worth showing: a member looking for "reply to support" should learn
 * that the reply arrives by email and why, not conclude the thread is broken.
 * The reason is wired to the button with aria-describedby, so a screen reader
 * announces it along with the disabled state instead of leaving the user to
 * guess why the button does nothing.
 */
export function LockedAction({
  label,
  reason,
  icon,
  className,
}: {
  label: string;
  reason: string;
  icon?: ReactNode;
  className?: string;
}) {
  const id = `locked-${label.toLowerCase().replace(/\W+/g, '-')}`;
  return (
    <div className={cn('space-y-1.5', className)}>
      <Button variant="secondary" size="sm" disabled aria-describedby={id}>
        {icon ?? <Lock aria-hidden="true" />}
        {label}
      </Button>
      <p id={id} className="flex max-w-prose items-start gap-1.5 text-xs text-muted-foreground">
        <AlertTriangle className="mt-0.5 size-3 shrink-0" aria-hidden="true" />
        {reason}
      </p>
    </div>
  );
}

/*
 * MEMBER_REPLY_UNAVAILABLE and MEMBER_CLOSE_UNAVAILABLE used to live here.
 *
 * Both are gone because the routines they asked for exist:
 * `v2_member_message_request(p_source, p_id, p_body)` and
 * `v2_member_close_ticket(p_id)`, migration 20260820150000. Each is SECURITY
 * DEFINER, resolves the member from `auth.uid()`, refuses a row that member
 * does not own with 42501, and writes the trust-bearing columns itself, so the
 * reply box and the close button on TicketDetail are now real controls. The
 * hooks that call them are `useReplyToTicket` and `useCloseTicket`.
 *
 * ASSIGN_UNAVAILABLE below is still unresolved and still describes a real gap.
 */

/**
 * Why staff cannot assign a ticket from the queue.
 *
 * `member_support_tickets` has no assignee column at all — only `resolved_by`,
 * written when a ticket is closed. `arx_support_tickets` does have
 * `assigned_to`, but its only policy scopes the row to the submitting club
 * member, so an administrator's direct UPDATE is filtered to zero rows and
 * returns 204 with no error. `v2_admin_update_request` takes a status and a
 * note and nothing else.
 */
export const ASSIGN_UNAVAILABLE =
  'member_support_tickets has no assignee column, and the assigned_to column on arx_support_tickets is behind a policy that scopes the row to the submitting club member, so an update from here would be filtered to zero rows and still report success. TODO(server): extend v2_admin_update_request with p_assignee uuid, and add the column to member_support_tickets.';

/* ---------------------------------------------------------------- thread */

interface ThreadQuery {
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  data: ThreadMessage[] | undefined;
  refetch: () => unknown;
}

/** Which side of the conversation the reader is on. */
export type Perspective = 'member' | 'staff';

/**
 * Turn a stored sender_role into a label.
 *
 * Roles are free text on the row, so anything unrecognised is treated as staff
 * rather than as the member — mislabelling a staff message as the member's own
 * is the more confusing of the two mistakes, and no name is shown either way.
 */
function senderLabel(role: string, perspective: Perspective): { label: string; mine: boolean } {
  const key = role.toLowerCase();
  const fromMember = key === 'member' || key === 'user';
  if (perspective === 'member') {
    return fromMember ? { label: 'You', mine: true } : { label: 'Support', mine: false };
  }
  return fromMember ? { label: 'Member', mine: false } : { label: 'Support', mine: true };
}

/**
 * The conversation on a ticket, oldest first.
 *
 * Nothing here identifies a person. `sender_id` and `user_id` are not fetched
 * (see hooks.ts), so the most a message can say is which side of the desk it
 * came from — which is all either reader needs and all a leaky policy on
 * `v2_request_messages` could give away through this component.
 */
export function Thread({
  query,
  perspective,
  emptyDescription,
}: {
  query: ThreadQuery;
  perspective: Perspective;
  emptyDescription?: string;
}) {
  if (query.isLoading) {
    return (
      <div className="space-y-3">
        <Skeleton className="h-16 w-full" />
        <Skeleton className="h-16 w-3/4" />
      </div>
    );
  }

  if (query.isError) {
    return (
      <ErrorState
        title="Could not load the conversation"
        error={query.error}
        onRetry={() => void query.refetch()}
      />
    );
  }

  const messages = query.data ?? [];
  if (messages.length === 0) {
    return (
      <EmptyState
        title="No messages yet"
        description={
          emptyDescription ??
          'Nothing has been added to this ticket since it was opened.'
        }
        icon={<MessageSquare className="size-5" />}
      />
    );
  }

  return (
    <ol className="space-y-3">
      {messages.map((message) => {
        const { label, mine } = senderLabel(message.sender_role, perspective);
        return (
          <li
            key={message.id}
            className={cn(
              'rounded-lg border p-3',
              mine ? 'border-primary/20 bg-primary/5' : 'border-border bg-elevated'
            )}
          >
            <div className="mb-1.5 flex flex-wrap items-center gap-2">
              <Badge tone={mine ? 'primary' : 'neutral'}>{label}</Badge>
              <span className="text-xs text-muted-foreground">
                {relativeTime(message.created_at)}
              </span>
            </div>
            <p className="whitespace-pre-wrap break-words text-sm">{message.body}</p>
            {message.requires_response && (
              <p className="mt-1.5 text-xs text-warning">A reply was requested.</p>
            )}
          </li>
        );
      })}
    </ol>
  );
}

/** The textarea treatment, matching Input. There is no textarea in the kit yet. */
export const TEXTAREA_CLASS =
  'flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm transition-colors placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50';

/**
 * The select treatment, matching Input.
 *
 * A native select is the right control for a short, known list: it is keyboard-
 * and screen-reader-complete without any of the roving-tabindex work a custom
 * listbox would need, and the design system has no listbox yet.
 */
export const SELECT_CLASS =
  'flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm transition-colors disabled:cursor-not-allowed disabled:opacity-50';
