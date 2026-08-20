import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';
import {
  useMessageRequest,
  useSupportTickets,
  useUpdateRequest,
} from '@/domains/operations/hooks';
import type { RequestSource } from '@/domains/operations/requestSources';

/**
 * Every read and write the support domain performs.
 *
 * Three rules hold throughout, and each one is why a control below is shaped
 * the way it is rather than the obvious way:
 *
 *  1. RLS is the boundary, not the query. `member_support_tickets` carries
 *     `USING (auth.uid() = user_id)` for SELECT and `WITH CHECK (auth.uid() =
 *     user_id)` for INSERT (mig 20251209063008). Nothing here relies on a
 *     client-side predicate to keep one member out of another's rows. Where a
 *     `.eq('user_id', …)` does appear it is a *view* filter and is commented as
 *     such — administrators hold a second, select-all policy on the same table,
 *     so without it the member-facing screens would render every member's
 *     tickets to a signed-in admin. That is a correctness problem, not the
 *     security one, and the two are kept clearly apart.
 *
 *  2. No column that names another person is ever selected. The thread reads
 *     `id, body, sender_role, requires_response, created_at` and deliberately
 *     omits `sender_id` and `user_id`; the ticket list omits `resolved_by`.
 *     A member sees *that* support replied, never *who*.
 *
 *  3. A write with no server routine behind it is not performed. The member
 *     reply and the member-side close both needed a `user_id`/`sender_role` the
 *     browser would have been choosing, or an UPDATE that RLS filters to zero
 *     rows and returns 200 with no error — v2's success-toast-for-nothing bug
 *     exactly. Both now have a routine: `v2_member_message_request` and
 *     `v2_member_close_ticket` (mig 20260820150000), each SECURITY DEFINER,
 *     each resolving the member from `auth.uid()` and refusing somebody else's
 *     row with 42501. The browser sends a ticket id and a body and nothing
 *     else, and — rule 4 — reads the result rather than assuming it.
 *
 *  4. Every write is checked by what came back, not by the absence of an error.
 *     A refused UPDATE is `200 []`, and a routine that returned nothing is a
 *     write that did not happen. Each mutation below asserts on the returned
 *     row and throws a sentence the member can act on if it is missing.
 */

type Tables = Database['public']['Tables'];

/* ------------------------------------------------------------- vocabulary */

/**
 * The values the table's own CHECK constraints permit.
 *
 * `member_support_tickets` constrains category, severity and status in the
 * database (mig 20251209063008:9-12). Offering anything outside these lists
 * produces a 23514 at insert time, so the form is built from the constraint
 * rather than from a hopeful guess.
 */
export const TICKET_CATEGORIES = [
  'profile_security',
  'voucher',
  'staking',
  'banking',
  'other',
] as const;
export type TicketCategory = (typeof TICKET_CATEGORIES)[number];

export const TICKET_SEVERITIES = ['low', 'medium', 'high', 'critical'] as const;
export type TicketSeverity = (typeof TICKET_SEVERITIES)[number];

export const MEMBER_TICKET_STATUSES = ['pending', 'in_progress', 'resolved', 'closed'] as const;

/** The source key `v2_request_messages` and the v2_admin_* RPCs use for a member ticket. */
export const MEMBER_TICKET_SOURCE: RequestSource = 'member_support_tickets';

/* ------------------------------------------------------------------ types */

/**
 * A member's own ticket, as the member sees it.
 *
 * `user_email`, `full_name`, `user_phone` and `str_domain` are the member's own
 * data and RLS would return them, but the screens do not render them back at
 * the person who typed them, so they are not fetched. `resolved_by` names a
 * member of staff and is never fetched at all.
 *
 * `admin_notes` is deliberately absent, and this is the one worth spelling out.
 * The member's SELECT policy does return it, so it is not secret — but it is
 * the internal note staff write for each other, it routinely refers to other
 * members and to internal process, and the operations screen labels it "Admin
 * notes" precisely because it is not written for the member to read. The
 * member-visible channel is the thread in `v2_request_messages`, which staff
 * write knowingly through `v2_admin_message_request`. Fetching a column the UI
 * must then be careful not to render is how it eventually gets rendered.
 */
export type MyTicket = Pick<
  Tables['member_support_tickets']['Row'],
  | 'id'
  | 'category'
  | 'severity'
  | 'status'
  | 'error_details'
  | 'resolution_time_hours'
  | 'created_at'
  | 'updated_at'
  | 'resolved_at'
>;

const MY_TICKET_COLUMNS =
  'id, category, severity, status, error_details, resolution_time_hours, created_at, updated_at, resolved_at';

/** One message in a ticket thread. Carries no identity of any kind. */
export type ThreadMessage = Pick<
  Tables['v2_request_messages']['Row'],
  'id' | 'body' | 'sender_role' | 'requires_response' | 'created_at'
>;

const THREAD_COLUMNS = 'id, body, sender_role, requires_response, created_at';

/* ------------------------------------------------------------------- keys */

/**
 * Query keys for this domain.
 *
 * Member keys carry the user id so that signing out and back in as somebody
 * else cannot serve the previous member's tickets from cache. The staff queue
 * has no user id in its key because it is not user-scoped data — it is read
 * through the operations loader and shares that domain's keys.
 */
export const sk = {
  all: ['support'] as const,
  myTickets: (userId: string) => ['support', 'my-tickets', userId] as const,
  ticket: (userId: string, id: string) => ['support', 'ticket', userId, id] as const,
  thread: (source: string, requestId: string) => ['support', 'thread', source, requestId] as const,
} as const;

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/** Throw on a Supabase error so react-query can surface it to an ErrorState. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

/* ------------------------------------------------------------------ reads */

/**
 * The signed-in member's tickets.
 *
 * The `.eq('user_id', …)` is a view filter, not the access control: RLS already
 * restricts a member to their own rows. It is here because administrators hold
 * `Admins can view all support tickets` on the same table, and without it the
 * "My tickets" page would list the whole platform's tickets to anyone who also
 * happens to be staff — a member-facing screen quietly turning into a queue.
 */
export function useMyTickets() {
  const userId = useUserId();
  return useQuery({
    queryKey: sk.myTickets(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<MyTicket[]> =>
      unwrap(
        await supabase
          .from('member_support_tickets')
          .select(MY_TICKET_COLUMNS)
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
          .limit(200)
      ) ?? [],
  });
}

/**
 * One ticket by id.
 *
 * Returns `null` rather than throwing when the id is not the member's: RLS
 * returns no row and `maybeSingle` turns that into null, which the detail page
 * renders as "not found" instead of as an error. An administrator reading
 * another member's ticket does so on the staff queue, which is role-guarded —
 * this route stays own-rows-only for everybody, hence the same view filter.
 */
export function useMyTicket(id: string | undefined) {
  const userId = useUserId();
  return useQuery({
    queryKey: sk.ticket(userId ?? 'anon', id ?? '-'),
    enabled: !!userId && !!id,
    queryFn: async (): Promise<MyTicket | null> =>
      unwrap(
        await supabase
          .from('member_support_tickets')
          .select(MY_TICKET_COLUMNS)
          .eq('user_id', userId!)
          .eq('id', id!)
          .maybeSingle()
      ),
  });
}

/**
 * The threaded conversation on one request.
 *
 * The table's SELECT policy has since been read and exercised: `Members read
 * their request messages` is `USING (user_id = auth.uid())`, alongside a
 * FOR ALL policy for administrators. Asking for another member's thread returns
 * `[]`, confirmed against a live project. The two containments below stay
 * anyway, because neither costs anything and both survive a policy edit:
 *
 *  - The query never runs speculatively. `enabled` is driven by the caller, and
 *    the member-facing caller only enables it once the ticket itself has come
 *    back from an RLS-scoped read — so an id the member does not own produces
 *    no thread request at all, whatever the message table's policy says.
 *  - The selected columns contain no identity, so even a permissive policy
 *    could not leak a name, an email or a user id through this screen.
 */
export function useTicketThread(
  source: string | null | undefined,
  requestId: string | null | undefined,
  enabled = true
) {
  return useQuery({
    queryKey: sk.thread(source ?? '-', requestId ?? '-'),
    enabled: enabled && !!source && !!requestId,
    queryFn: async (): Promise<ThreadMessage[]> =>
      unwrap(
        await supabase
          .from('v2_request_messages')
          .select(THREAD_COLUMNS)
          .eq('source', source!)
          .eq('request_id', requestId!)
          .order('created_at', { ascending: true })
      ) ?? [],
  });
}

/* -------------------------------------------------------------- the queue */

/**
 * The staff queue reads through the operations domain, on purpose.
 *
 * `member_support_tickets` and `arx_support_tickets` already have one typed,
 * column-listed loader in `@/domains/operations/requestSources`, one decision
 * RPC and one message RPC. A second copy here would be a second set of columns
 * to keep in step with the schema and a second audit trail to reconcile — which
 * is precisely the v2 failure that file documents, where AdminSupportTickets
 * wrote the table directly while AdminV2Requests decided the same rows through
 * the RPC. These are aliases, not reimplementations: this domain puts a richer
 * surface over the same data, not a second way to reach it.
 */
export { SUPPORT_SOURCES } from '@/domains/operations/hooks';
export type { RequestItem, RequestSource } from '@/domains/operations/requestSources';

/** Both support queues, loaded by the operations loader. */
export const useSupportQueue = useSupportTickets;

/** Status decisions, recorded by `v2_admin_update_request` with its audit row. */
export const useQueueDecision = useUpdateRequest;

/** Staff replies, written by `v2_admin_message_request`. */
export const useQueueReply = useMessageRequest;

/**
 * The statuses each queue actually accepts.
 *
 * `member_support_tickets.status` has a CHECK constraint permitting exactly
 * pending / in_progress / resolved / closed. The operations screen also offers
 * `rejected` and `escalated` for this source, and both violate that constraint
 * — see the note accompanying this domain. The list here is the constraint.
 *
 * `arx_support_tickets.status` is plain text with a default of 'open' and no
 * constraint, so its list is the vocabulary the ARX workflow uses.
 */
export const QUEUE_STATUSES: Record<string, readonly string[]> = {
  member_support_tickets: ['pending', 'in_progress', 'resolved', 'closed'],
  arx_support_tickets: ['open', 'in_progress', 'escalated', 'resolved', 'closed'],
};

/* -------------------------------------------------------------- mutations */

export interface OpenTicketInput {
  category: TicketCategory;
  severity: TicketSeverity;
  details: string;
}

/**
 * Open a support ticket.
 *
 * This is the one write in the domain the browser is allowed to make, and it is
 * allowed because every column it sets is either a constant or the member's own
 * identity taken from the session — `user_id` comes from the session on the
 * client *and* is checked against `auth.uid()` by the INSERT policy, so a client
 * that names somebody else is refused by the database rather than trusted.
 *
 * `.select('id').single()` is not decoration. An insert RLS refuses does raise
 * an error, but asking for the row back turns "wrote nothing" into a thrown
 * error in every case rather than in most of them, which is the rule the rest
 * of this rebuild follows for writes.
 */
export function useOpenTicket() {
  const qc = useQueryClient();
  const { user } = useAuth();
  return useMutation({
    mutationFn: async (input: OpenTicketInput): Promise<string> => {
      const userId = user?.id;
      const email = user?.email;
      if (!userId) throw new Error('Your session has expired. Sign in again and retry.');
      // user_email is NOT NULL on the table. An account with no email address
      // cannot satisfy that, and the form disables submission for this reason
      // rather than sending a placeholder staff would then try to reply to.
      if (!email) throw new Error('Your account has no email address, so a ticket cannot be raised.');

      const details = input.details.trim();
      if (!details) throw new Error('Describe the problem before sending.');

      const metaName = user?.user_metadata?.full_name;
      const fullName = typeof metaName === 'string' && metaName.trim() ? metaName.trim() : null;

      const { data, error } = await supabase
        .from('member_support_tickets')
        .insert({
          user_id: userId,
          user_email: email,
          full_name: fullName,
          category: input.category,
          severity: input.severity,
          error_details: details,
          status: 'pending',
        })
        .select('id')
        .single();

      if (error) throw new Error(error.message);
      if (!data) throw new Error('The ticket was not created. Nothing has been sent.');
      return data.id;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: sk.all });
    },
  });
}

/**
 * The most a reply is allowed to be.
 *
 * `v2_member_message_request` raises 22001 above 5000 characters. The number is
 * repeated here so the textarea can stop at the limit and show a counter rather
 * than let the member write an essay and then lose it to a server error.
 */
export const REPLY_MAX_LENGTH = 5000;

/**
 * Read a jsonb RPC result as an object without asserting it is one.
 *
 * The generated type for these routines is `Json`, which is a union that
 * includes null, a string and an array. Narrowing rather than casting is what
 * makes the "did the write actually happen" check below real: a routine that
 * returned null reaches the `throw`, it does not reach a property access on
 * something that is not there.
 */
function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

/**
 * Reply to support on your own ticket.
 *
 * Everything that decides whose thread this lands in and who it appears to be
 * from is chosen by the database. The browser sends a source, a ticket id and
 * some text; `v2_member_message_request` resolves the member from `auth.uid()`,
 * refuses a ticket that member does not own with 42501, and writes `user_id`,
 * `sender_id` and `sender_role` itself. The member INSERT policy that used to
 * sit on `v2_request_messages` was dropped in the same migration — it pinned
 * the sender but never checked the thread, so it let a member post into another
 * member's ticket, which an administrator working the queue would then read.
 *
 * The returned message id is checked. A routine that returns nothing has not
 * written anything, and telling the member their reply is on its way when it is
 * not is the failure this rebuild exists to remove.
 */
export function useReplyToTicket() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { ticketId: string; body: string }): Promise<void> => {
      const body = input.body.trim();
      if (!body) throw new Error('Write something before sending.');
      if (body.length > REPLY_MAX_LENGTH) {
        throw new Error(`A reply can be at most ${REPLY_MAX_LENGTH} characters.`);
      }

      const { data, error } = await supabase.rpc('v2_member_message_request', {
        p_source: MEMBER_TICKET_SOURCE,
        p_id: input.ticketId,
        p_body: body,
      });
      if (error) throw new Error(error.message);

      const message = asRecord(data);
      if (typeof message?.id !== 'string') {
        throw new Error('The reply was not saved. Nothing has been sent to support.');
      }
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: sk.all });
    },
  });
}

/** What `v2_member_close_ticket` reports back. */
export interface CloseTicketResult {
  status: string;
  /** False when the ticket was already closed — the call succeeded and did nothing. */
  changed: boolean;
}

/**
 * Close your own ticket.
 *
 * A direct `UPDATE` from the browser is the exact shape of finding F-055: there
 * is no member UPDATE policy on `member_support_tickets`, so PostgREST returns
 * `200 []` with no error and the UI congratulates the member on a change that
 * never happened. `v2_member_close_ticket` is SECURITY DEFINER, scoped to
 * `auth.uid()`, and its UPDATE statement can set `status` and nothing else —
 * `resolved_by` and `resolved_at` stay untouched because a ticket the member
 * closed was not resolved by a member of staff.
 *
 * The status that comes back is read rather than trusted: anything other than
 * `closed` is reported as a failure, so a routine that silently declined would
 * surface as one.
 */
export function useCloseTicket() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (ticketId: string): Promise<CloseTicketResult> => {
      const { data, error } = await supabase.rpc('v2_member_close_ticket', {
        p_id: ticketId,
      });
      if (error) throw new Error(error.message);

      const row = asRecord(data);
      const status = typeof row?.status === 'string' ? row.status : null;
      if (!status) {
        throw new Error('The ticket was not closed. Nothing on it has changed.');
      }
      if (status.toLowerCase() !== 'closed') {
        throw new Error(`The ticket was not closed — it is still ${status.replace(/_/g, ' ')}.`);
      }
      return { status, changed: row?.changed === true };
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: sk.all });
    },
  });
}
