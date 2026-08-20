import { useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { toast } from 'sonner';
import { ArrowLeft, CheckCircle2, SearchX, Send } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Field } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { shortDate } from '@/lib/format';
import {
  useCloseTicket,
  useMyTicket,
  useReplyToTicket,
  useTicketThread,
  MEMBER_TICKET_SOURCE,
  REPLY_MAX_LENGTH,
} from './hooks';
import {
  categoryLabel,
  Detail,
  isTicketOpen,
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
 *
 * The two writes on this page — reply and close — go through
 * `v2_member_message_request` and `v2_member_close_ticket`. Neither sends a
 * user id, a sender role or a status; the ticket id and the text are the whole
 * payload, and the database decides the rest from the session. Both check what
 * came back before saying anything encouraging, because a refused write on this
 * platform is a `200` with an empty body, not an error.
 */

/**
 * The member's reply box.
 *
 * The payload is a ticket id and some text. `user_id`, `sender_id` and
 * `sender_role` are written by the routine from `auth.uid()`, which is what
 * makes this box safe to render at all: a browser that chose `sender_role`
 * could post a message the thread would render as coming from support.
 *
 * The draft is only cleared once the mutation has resolved and the routine has
 * returned a message id. If the send fails the member still has what they
 * typed, which is the difference between a retry and re-writing it.
 */
function ReplyBox({ ticketId }: { ticketId: string }) {
  const [body, setBody] = useState('');
  const reply = useReplyToTicket();
  const trimmed = body.trim();
  const canSend = trimmed.length > 0 && trimmed.length <= REPLY_MAX_LENGTH && !reply.isPending;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSend) return;
    try {
      await reply.mutateAsync({ ticketId, body });
      setBody('');
      toast.success('Your reply has been added to the ticket.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Your reply was not sent.');
    }
  }

  return (
    <form className="mt-5 space-y-3 border-t border-border pt-4" onSubmit={(e) => void submit(e)}>
      <Field
        label="Reply"
        htmlFor="ticket-reply"
        hint={`${trimmed.length}/${REPLY_MAX_LENGTH} · support sees this on the ticket. Never include a password, a PIN or a recovery phrase.`}
      >
        <textarea
          id="ticket-reply"
          rows={3}
          maxLength={REPLY_MAX_LENGTH}
          className={TEXTAREA_CLASS}
          value={body}
          disabled={reply.isPending}
          onChange={(e) => setBody(e.target.value)}
          placeholder="Add anything that would help, or answer what support asked."
        />
      </Field>
      <Button type="submit" size="sm" disabled={!canSend}>
        <Send aria-hidden="true" />
        {reply.isPending ? 'Sending…' : 'Send reply'}
      </Button>
    </form>
  );
}

/**
 * Close your own ticket.
 *
 * Two steps rather than one: closing is the only thing on this screen a member
 * cannot undo themselves, and a single button beside a reply box is easy to hit
 * by accident.
 *
 * The success message is driven by what the routine reported. `changed: false`
 * means the ticket was already closed — a call that succeeded and did nothing —
 * and saying so is more honest than a second "Closed." for a click that moved
 * nothing.
 */
function CloseTicket({ ticketId }: { ticketId: string }) {
  const [confirming, setConfirming] = useState(false);
  const close = useCloseTicket();

  async function run() {
    try {
      const result = await close.mutateAsync(ticketId);
      setConfirming(false);
      toast.success(
        result.changed
          ? 'Ticket closed. You can still add a reply if something changes.'
          : 'This ticket was already closed.'
      );
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The ticket was not closed.');
    }
  }

  if (!confirming) {
    return (
      <div className="space-y-1.5">
        <Button variant="secondary" size="sm" onClick={() => setConfirming(true)}>
          <CheckCircle2 aria-hidden="true" />
          Close this ticket
        </Button>
        <p className="max-w-prose text-xs text-muted-foreground">
          Close it once your problem is solved. Support can reopen it, and you can still add a
          reply afterwards.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <p className="max-w-prose text-sm">
        Close this ticket? Support will stop working on it unless you reply again.
      </p>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" disabled={close.isPending} onClick={() => void run()}>
          {close.isPending ? 'Closing…' : 'Yes, close it'}
        </Button>
        <Button
          variant="ghost"
          size="sm"
          disabled={close.isPending}
          onClick={() => setConfirming(false)}
        >
          Keep it open
        </Button>
      </div>
    </div>
  );
}

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
  // `isTicketOpen` answers "is somebody still working on this", which excludes
  // `resolved`. Closing is a different question: a resolved ticket is exactly
  // the one a member wants to close, so the control is offered on anything that
  // is not already closed.
  const closable = row.status.toLowerCase() !== 'closed';

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

            <ReplyBox ticketId={row.id} />
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
            description="What you can do to this ticket yourself."
          >
            {closable ? (
              <CloseTicket ticketId={row.id} />
            ) : (
              <p className="flex max-w-prose items-start gap-2 text-sm text-muted-foreground">
                <CheckCircle2 className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
                This ticket is {row.status.replace(/_/g, ' ')}. Replying to it is still open to
                you if something changes.
              </p>
            )}
          </Section>
        </div>
      </div>
    </>
  );
}
