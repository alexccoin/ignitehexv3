import { useMemo, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { LifeBuoy, Send, Ticket } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Field } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { useAuth } from '@/features/auth/AuthProvider';
import { relativeTime, shortDate } from '@/lib/format';
import {
  useMyTickets,
  useOpenTicket,
  TICKET_CATEGORIES,
  TICKET_SEVERITIES,
  type MyTicket,
  type TicketCategory,
  type TicketSeverity,
} from './hooks';
import {
  categoryLabel,
  isTicketOpen,
  Section,
  SeverityBadge,
  SELECT_CLASS,
  TEXTAREA_CLASS,
} from './shared';

/**
 * The member's own support desk.
 *
 * v2 put "report a problem" behind a floating widget on one page, a form in the
 * profile screen and a third form in the banking area, none of which showed the
 * member what had happened to anything they had already sent — so the commonest
 * support request in the platform was "did you get my last message?". Here the
 * list and the form are the same screen: what you sent, what state it is in,
 * and one place to send another.
 */

const SEVERITY_HINT: Record<TicketSeverity, string> = {
  low: 'A question or something cosmetic.',
  medium: 'Something is wrong but you can keep using the platform.',
  high: 'You cannot complete something important.',
  critical: 'Funds or account access are affected.',
};

function TicketRow({ ticket }: { ticket: MyTicket }) {
  const open = isTicketOpen(ticket.status);
  return (
    <li>
      <Link
        to={`/support/ticket/${ticket.id}`}
        className="block rounded-lg border border-border p-4 transition-colors hover:bg-elevated"
      >
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="font-medium">{categoryLabel(ticket.category)}</p>
            <p className="line-clamp-2 text-sm text-muted-foreground">{ticket.error_details}</p>
          </div>
          <div className="flex shrink-0 flex-wrap items-center gap-2">
            <SeverityBadge severity={ticket.severity} />
            <StatusBadge status={ticket.status} />
          </div>
        </div>
        <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
          <span>Opened {relativeTime(ticket.created_at)}</span>
          {ticket.resolved_at ? (
            <span>Resolved {shortDate(ticket.resolved_at)}</span>
          ) : open && ticket.resolution_time_hours ? (
            <span>Target response {ticket.resolution_time_hours}h</span>
          ) : null}
        </div>
      </Link>
    </li>
  );
}

/**
 * The one write this domain makes from the browser.
 *
 * Every field it sets is the member's own: the category and severity come from
 * the two CHECK constraints on the table, the description is what they typed,
 * and the identity is read from the session and checked again by the INSERT
 * policy. Nothing on this form names another person or a status.
 */
function OpenTicketForm() {
  const { user } = useAuth();
  const open = useOpenTicket();
  const [category, setCategory] = useState<TicketCategory>('other');
  const [severity, setSeverity] = useState<TicketSeverity>('medium');
  const [details, setDetails] = useState('');

  // The table requires an email address on every ticket, so an account without
  // one cannot raise a ticket at all. Saying so is better than a 23502 from the
  // database after the member has typed out their problem.
  const missingEmail = !user?.email;
  const canSend = !missingEmail && details.trim().length >= 10 && !open.isPending;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSend) return;
    try {
      await open.mutateAsync({ category, severity, details });
      toast.success('Ticket raised. Support can see it now.');
      setDetails('');
      setCategory('other');
      setSeverity('medium');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The ticket could not be raised.');
    }
  }

  return (
    <Section
      title="Open a ticket"
      description="Support sees this immediately. Do not include passwords, PINs or recovery phrases — nobody here will ever ask for them."
    >
      <form className="space-y-4" onSubmit={(e) => void submit(e)}>
        <Field label="What is it about" htmlFor="ticket-category">
          <select
            id="ticket-category"
            className={SELECT_CLASS}
            value={category}
            onChange={(e) => setCategory(e.target.value as TicketCategory)}
          >
            {TICKET_CATEGORIES.map((value) => (
              <option key={value} value={value}>
                {categoryLabel(value)}
              </option>
            ))}
          </select>
        </Field>

        <Field label="How badly is it affecting you" htmlFor="ticket-severity" hint={SEVERITY_HINT[severity]}>
          <select
            id="ticket-severity"
            className={SELECT_CLASS}
            value={severity}
            onChange={(e) => setSeverity(e.target.value as TicketSeverity)}
          >
            {TICKET_SEVERITIES.map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </Field>

        <Field
          label="What happened"
          htmlFor="ticket-details"
          hint={
            missingEmail
              ? undefined
              : `${details.trim().length}/2000 · at least 10 characters, and dates or amounts help.`
          }
          error={
            missingEmail
              ? 'Your account has no email address, so support would have no way to reply. Add one on the Account page first.'
              : undefined
          }
        >
          <textarea
            id="ticket-details"
            rows={6}
            maxLength={2000}
            className={TEXTAREA_CLASS}
            value={details}
            disabled={missingEmail}
            onChange={(e) => setDetails(e.target.value)}
            placeholder="What you were doing, what you expected, and what happened instead."
          />
        </Field>

        <Button type="submit" disabled={!canSend}>
          <Send aria-hidden="true" />
          {open.isPending ? 'Sending…' : 'Send to support'}
        </Button>
      </form>
    </Section>
  );
}

export default function MyTickets() {
  const tickets = useMyTickets();

  const counts = useMemo(() => {
    const items = tickets.data ?? [];
    return {
      open: items.filter((t) => isTicketOpen(t.status)).length,
      inProgress: items.filter((t) => t.status.toLowerCase() === 'in_progress').length,
      resolved: items.filter((t) => t.status.toLowerCase() === 'resolved').length,
    };
  }, [tickets.data]);

  return (
    <>
      <PageHeader
        title="Support"
        description="Everything you have asked us about, and where each one stands."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat label="Open" value={counts.open} loading={tickets.isLoading} tone="primary" />
        <Stat label="Being worked on" value={counts.inProgress} loading={tickets.isLoading} />
        <Stat label="Resolved" value={counts.resolved} loading={tickets.isLoading} tone="success" />
      </div>

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="space-y-6 lg:col-span-3">
          <Section title="Your tickets" description="Newest first. Open one to read the conversation.">
            {tickets.isLoading ? (
              <div className="space-y-3">
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
                <Skeleton className="h-24 w-full" />
              </div>
            ) : tickets.isError ? (
              <ErrorState
                title="Could not load your tickets"
                error={tickets.error}
                onRetry={() => void tickets.refetch()}
              />
            ) : (tickets.data ?? []).length === 0 ? (
              <EmptyState
                title="No tickets yet"
                description="Nothing has been raised on this account. Use the form to tell us about a problem."
                icon={<Ticket className="size-5" />}
              />
            ) : (
              <ul className="space-y-3">
                {(tickets.data ?? []).map((ticket) => (
                  <TicketRow key={ticket.id} ticket={ticket} />
                ))}
              </ul>
            )}
          </Section>

          <Card>
            <CardContent className="flex items-start gap-3 py-4">
              <LifeBuoy className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
              <p className="text-sm text-muted-foreground">
                Looking for an answer rather than a person?{' '}
                <Link to="/support/help" className="text-primary underline-offset-4 hover:underline">
                  Answers
                </Link>{' '}
                is where published help articles will appear. Replies to your tickets arrive in
                the ticket itself.
              </p>
            </CardContent>
          </Card>
        </div>

        <div className="lg:col-span-2">
          <OpenTicketForm />
        </div>
      </div>
    </>
  );
}
