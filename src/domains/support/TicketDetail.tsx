import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, MessageSquare, SearchX } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { shortDate } from '@/lib/format';
import { useMyTicket, useTicketThread, MEMBER_TICKET_SOURCE } from './hooks';
import {
  categoryLabel,
  Detail,
  isTicketOpen,
  LockedAction,
  MEMBER_CLOSE_UNAVAILABLE,
  MEMBER_REPLY_UNAVAILABLE,
  Section,
  SeverityBadge,
  TEXTAREA_CLASS,
  Thread,
} from './shared';

/**
 * One ticket, and the conversation on it.
 *
 * The ordering here is the security-relevant part. The ticket is read first,
 * through a policy that only returns the member's own rows; the thread query is
 * enabled only once that read has produced a ticket. An id belonging to someone
 * else therefore results in *no request at all* against `v2_request_messages`,
 * which matters because that table's policy is not in the repository and cannot
 * be verified from here. The UI does not depend on it being right, and the
 * columns it asks for could not identify anybody if it were wrong.
 *
 * v2's equivalent screen took the id straight from the URL and queried the
 * message table with it, so what the member saw was decided entirely by a
 * policy nobody had read.
 */

function BackLink() {
  return (
    <Button asChild variant="ghost" size="sm" className="mb-4 -ml-3">
      <Link to="/support">
        <ArrowLeft aria-hidden="true" />
        All tickets
      </Link>
    </Button>
  );
}

export default function TicketDetail() {
  const { id } = useParams<{ id: string }>();
  const ticket = useMyTicket(id);

  // Only ask for the conversation once the ticket has come back from an
  // RLS-scoped read. `isSuccess` alone is not enough — a successful read that
  // returned null is exactly the not-yours case.
  const found = ticket.isSuccess && ticket.data !== null;
  const thread = useTicketThread(MEMBER_TICKET_SOURCE, id, found);

  if (ticket.isLoading) {
    return (
      <>
        <BackLink />
        <Skeleton className="mb-6 h-24 w-full" />
        <Skeleton className="h-64 w-full" />
      </>
    );
  }

  if (ticket.isError) {
    return (
      <>
        <BackLink />
        <Card>
          <ErrorState
            title="Could not load this ticket"
            error={ticket.error}
            onRetry={() => void ticket.refetch()}
          />
        </Card>
      </>
    );
  }

  if (!ticket.data) {
    return (
      <>
        <BackLink />
        <Card>
          <EmptyState
            title="Ticket not found"
            description="This ticket does not exist on your account. If you followed a link from an email, check that you are signed in as the right member."
            icon={<SearchX className="size-5" />}
            action={
              <Button asChild variant="secondary" size="sm">
                <Link to="/support">Back to your tickets</Link>
              </Button>
            }
          />
        </Card>
      </>
    );
  }

  const row = ticket.data;
  const open = isTicketOpen(row.status);

  return (
    <>
      <BackLink />
      <PageHeader
        title={categoryLabel(row.category)}
        description={`Opened ${shortDate(row.created_at)}`}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={row.severity} />
            <StatusBadge status={row.status} />
          </div>
        }
      />

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="space-y-6 lg:col-span-3">
          <Section title="What you reported">
            <p className="whitespace-pre-wrap break-words text-sm">{row.error_details}</p>
          </Section>

          <Section
            title="Conversation"
            description="Messages from support appear here as they are sent."
          >
            <Thread
              query={thread}
              perspective="member"
              emptyDescription={
                open
                  ? 'Support has not replied yet. You will get an email when they do, and the reply will show up here.'
                  : 'This ticket was closed without any messages being added.'
              }
            />

            {/* The reply box is rendered rather than omitted so the thread does
                not look one-directional by accident, and disabled because the
                write behind it would have the browser choosing whose thread the
                message lands in and whether it is labelled as staff. */}
            <div className="mt-5 space-y-2 border-t border-border pt-4">
              <label className="text-sm font-medium" htmlFor="ticket-reply">
                Reply
              </label>
              <textarea
                id="ticket-reply"
                rows={3}
                disabled
                className={TEXTAREA_CLASS}
                placeholder="Replying from here is not available yet."
                aria-describedby="locked-reply-to-support"
              />
              <LockedAction
                label="Reply to support"
                reason={MEMBER_REPLY_UNAVAILABLE}
                icon={<MessageSquare aria-hidden="true" />}
              />
            </div>
          </Section>
        </div>

        <div className="space-y-6 lg:col-span-2">
          <Section title="Status">
            <div className="space-y-4">
              <Detail label="Current status" value={<StatusBadge status={row.status} />} />
              <Detail label="Severity" value={<SeverityBadge severity={row.severity} />} />
              <Detail label="Opened" value={shortDate(row.created_at)} />
              <Detail label="Last updated" value={shortDate(row.updated_at)} />
              {row.resolved_at && <Detail label="Resolved" value={shortDate(row.resolved_at)} />}
              {open && row.resolution_time_hours !== null && (
                <Detail
                  label="Target response"
                  value={`${row.resolution_time_hours} hours from opening`}
                />
              )}
            </div>
          </Section>

          <Section
            title="Anything else"
            description="What you can and cannot do to this ticket yourself."
          >
            <LockedAction label="Close this ticket" reason={MEMBER_CLOSE_UNAVAILABLE} />
          </Section>
        </div>
      </div>
    </>
  );
}
