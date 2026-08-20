import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database, Json } from '@/lib/database.types';
import { serviceName, type ServiceKey } from './properties';

/**
 * Every read and write the identity domain performs.
 *
 * IgniteHeX is the identity provider. A member signs in here once; everything
 * below is a *link* from that one identity to an account on a sibling property.
 * So there is no second password field in this domain, no external credential
 * is written from the browser, and no external credential is ever read into it
 * — see `DOMAIN_LINK_COLS` for the one column that is deliberately absent.
 *
 * Three facts about the database shape this file, all of them established by
 * running the statements against the local stack rather than by reading the
 * policy text:
 *
 *  1. A member cannot grant themselves `connected`. Both the INSERT policy and
 *     the own-UPDATE policy's WITH CHECK restrict the status a member may write
 *     to `not_connected` or `requested`, and PostgREST answers 42501 for the
 *     attempt. That is the one guarantee this feature rests on, and it holds.
 *
 *  2. A member can only touch a row that is *currently* `not_connected` or
 *     `rejected`. The own-UPDATE policy's USING clause names those two states
 *     and no others, so an update aimed at a `requested`, `pending_review`,
 *     `connected` or `suspended` row matches zero rows — and PostgREST answers
 *     `200 []` with no error. There is no DELETE policy at all, so a delete
 *     answers the same way from every state.
 *
 *  3. Consequently every write here uses `.select('id')` and treats an empty
 *     result as a failure. A write that changes nothing and reports no error is
 *     exactly the shape v2 turned into a green toast.
 */

type Tables = Database['public']['Tables'];

/* ------------------------------------------------------------------- types */

export type IdentityAccount = Pick<
  Tables['v2_accounts']['Row'],
  | 'id'
  | 'status'
  | 'account_mode'
  | 'email'
  | 'full_name'
  | 'str_domain'
  | 'submitted_at'
  | 'reviewed_at'
  | 'created_at'
>;

export type ServiceConnection = Pick<
  Tables['v2_service_connections']['Row'],
  | 'id'
  | 'service'
  | 'status'
  | 'external_reference'
  | 'metadata'
  | 'requested_at'
  | 'connected_at'
  | 'created_at'
  | 'updated_at'
>;

export type QueueConnection = ServiceConnection & { user_id: string; account_id: string };

export type DomainLink = Pick<
  Tables['str_domain_connections']['Row'],
  'id' | 'domain_name' | 'connection_status' | 'last_sync' | 'created_at' | 'updated_at'
>;

export type OwnedDomain = Pick<
  Tables['str_domains']['Row'],
  'id' | 'domain_name' | 'status' | 'is_main_domain'
>;

export type ConnectionAudit = Pick<
  Tables['v2_admin_actions']['Row'],
  'id' | 'entity_id' | 'action' | 'from_status' | 'to_status' | 'notes' | 'created_at'
>;

/* --------------------------------------------------------------- constants */

const CONNECTION_COLS =
  'id, service, status, external_reference, metadata, requested_at, connected_at, created_at, updated_at';

/**
 * The same columns plus the two the queue needs to identify whose link it is.
 *
 * Written out rather than concatenated from CONNECTION_COLS: supabase-js parses
 * the select string as a *literal type* to work out the row shape, and a
 * concatenation widens it to `string`, at which point the result degrades to an
 * error type and the only way through is a cast. Duplication here buys a
 * checked return type, which is the better trade.
 */
const QUEUE_COLS =
  'id, user_id, account_id, service, status, external_reference, metadata, requested_at, connected_at, created_at, updated_at';

/**
 * Note the absence of `api_key`.
 *
 * `str_domain_connections` carries an `api_key` column and its only RLS policy
 * is a SELECT for the owning user across every column — so a member's browser
 * *can* read it, and `select('*')` does. Verified against the local stack: with
 * a value in the column, `select=*` as the owning member returned the key in
 * full. Nothing on these screens renders it, so nothing here requests it. The
 * finding is recorded in docs/FINDINGS.md; the real fix is a column-level
 * revoke or a view, not a convention.
 */
const DOMAIN_LINK_COLS = 'id, domain_name, connection_status, last_sync, created_at, updated_at';

/**
 * The statuses a member's own row must currently hold for the member to be able
 * to change it, mirrored from the RLS policy's USING clause.
 *
 * Kept as data rather than folded into a condition because both the button
 * state and the refusal message need it, and those two drifting apart is how a
 * disabled control ends up with the wrong explanation.
 */
export const MEMBER_WRITABLE_FROM = ['not_connected', 'rejected'] as const;

/** Whether the member's own row is, from the member's side, frozen. */
export function isMemberFrozen(status: string | null | undefined): boolean {
  const current = status ?? 'not_connected';
  return !MEMBER_WRITABLE_FROM.some((s) => s === current);
}

/* --------------------------------------------------------------- utilities */

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/** Throw on a Supabase error so react-query surfaces it to an ErrorState. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

/** Rows a write actually touched. `null` and `[]` both mean nothing changed. */
function affectedRows(rows: unknown[] | null): number {
  return rows?.length ?? 0;
}

/** jsonb comes back as `Json`; every reader here wants an object. */
export function asRecord(value: Json | null | undefined): Record<string, Json> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, Json>)
    : {};
}

/** A metadata value as a display string, or null when it is absent. */
export function metadataString(value: Json | null | undefined, key: string): string | null {
  const raw = asRecord(value)[key];
  if (raw === null || raw === undefined) return null;
  if (typeof raw === 'string') return raw.trim() ? raw : null;
  if (typeof raw === 'number' || typeof raw === 'boolean') return String(raw);
  return null;
}

/** Query keys for the domain, namespaced under its id. */
export const ik = {
  all: ['identity'] as const,
  account: (userId: string) => ['identity', 'account', userId] as const,
  connections: (userId: string) => ['identity', 'connections', userId] as const,
  domainLinks: (userId: string) => ['identity', 'domain-links', userId] as const,
  ownedDomains: (userId: string) => ['identity', 'owned-domains', userId] as const,
  audit: (userId: string) => ['identity', 'audit', userId] as const,
  queue: (status: string) => ['identity', 'admin', 'queue', status] as const,
} as const;

/* ------------------------------------------------------------ member reads */

/**
 * The verified identity record every connection hangs off.
 *
 * `v2_service_connections.account_id` is NOT NULL and references
 * `v2_accounts(id)`, so a member with no account record cannot hold a link at
 * all. That is a real state — `v2_accounts` was empty on this deployment — and
 * the index route renders it as an empty state pointing at /account rather than
 * offering buttons that would fail on the foreign key.
 */
export function useIdentityAccount() {
  const userId = useUserId();
  return useQuery({
    queryKey: ik.account(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<IdentityAccount | null> =>
      unwrap(
        await supabase
          .from('v2_accounts')
          .select(
            'id, status, account_mode, email, full_name, str_domain, submitted_at, reviewed_at, created_at'
          )
          .eq('user_id', userId!)
          .maybeSingle()
      ),
  });
}

/** Every service link held against this identity, whether or not it has a card. */
export function useServiceConnections() {
  const userId = useUserId();
  return useQuery({
    queryKey: ik.connections(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<ServiceConnection[]> =>
      unwrap(
        await supabase
          .from('v2_service_connections')
          .select(CONNECTION_COLS)
          .eq('user_id', userId!)
          .order('service')
      ) ?? [],
  });
}

/**
 * The per-domain links beneath the str.domains service link.
 *
 * `str_domain_connections` is not a parallel model of the same thing: it is one
 * row per *domain*, where `v2_service_connections` is one row per *service*
 * (a UNIQUE constraint on (user_id, service) enforces exactly that). The
 * service row says "this identity is linked to str.domains"; these rows say
 * "and these specific domains are registered with the network". They are shown
 * nested under the str.domains card for that reason, not given cards of their
 * own.
 */
export function useDomainLinks() {
  const userId = useUserId();
  return useQuery({
    queryKey: ik.domainLinks(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<DomainLink[]> =>
      unwrap(
        await supabase
          .from('str_domain_connections')
          .select(DOMAIN_LINK_COLS)
          .eq('user_id', userId!)
          .order('domain_name')
      ) ?? [],
  });
}

/** Domains the member holds, offered as the reference on a str.domains request. */
export function useOwnedDomains() {
  const userId = useUserId();
  return useQuery({
    queryKey: ik.ownedDomains(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<OwnedDomain[]> =>
      unwrap(
        await supabase
          .from('str_domains')
          .select('id, domain_name, status, is_main_domain')
          .eq('user_id', userId!)
          .order('domain_name')
      ) ?? [],
  });
}

/**
 * Recorded decisions on this member's links.
 *
 * `v2_admin_actions` is the platform's decision log and a member may read their
 * own rows. It is queried honestly rather than optimistically: nothing writes
 * connection rows into it today — `v2_service_connections` carries only a
 * touch-updated_at trigger, and the log has no INSERT policy for any client
 * role (verified: a member INSERT answers 42501) — so this returns empty and
 * the Activity screen says why instead of leaving a blank panel.
 */
export function useConnectionAudit() {
  const userId = useUserId();
  return useQuery({
    queryKey: ik.audit(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<ConnectionAudit[]> =>
      unwrap(
        await supabase
          .from('v2_admin_actions')
          .select('id, entity_id, action, from_status, to_status, notes, created_at')
          .eq('user_id', userId!)
          .eq('entity_type', 'service_connection')
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

/* ----------------------------------------------------------- member writes */

export interface ConnectionRequest {
  service: ServiceKey;
  accountId: string;
  /** The row already held for this service, if any. */
  existing: ServiceConnection | null;
  /** Property-specific detail, merged into `metadata`. */
  metadataKey: string;
  metadataValue: string;
}

/**
 * Ask to link this identity to a property.
 *
 * This is a request and nothing more. `status` is written as `requested`; the
 * move to `connected` belongs to whatever eventually verifies the account on
 * the far side, and the database refuses the client either way.
 *
 * `metadata` carries the property's own reference — the str domain name, the
 * str.dome username, the bank reference — rather than a new column per
 * property, which is what the jsonb column is for.
 */
/**
 * End a link, or withdraw a request that has not been decided.
 *
 * This is what F-055 was about. The own-update policy's USING clause admits
 * only `not_connected` and `rejected` rows, so a member holding a `connected`
 * or `requested` link matched zero rows on every attempt — and PostgREST
 * answers that with `200 []` and no error, which is indistinguishable from
 * success to any caller that only inspects `error`.
 *
 * `v2_member_set_connection` resolves the member from auth.uid() and permits
 * only the transitions a member may make. `connected`, `pending_review` and
 * `suspended` are refused with 42501 — verified, not assumed — so the guarantee
 * this domain rests on is unchanged: a member cannot grant themselves a link.
 *
 * It changes a link record held by IgniteHeX. Nothing here contacts the far
 * property, because no API to it exists on this deployment. The UI says so.
 */
export function useSetConnectionState() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { service: ServiceKey; status: 'requested' | 'not_connected' }) => {
      if (!userId) throw new Error('You must be signed in.');
      const { error } = await supabase.rpc('v2_member_set_connection', {
        p_service: input.service,
        p_status: input.status,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['identity'] });
    },
  });
}

export function useRequestConnection() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: ConnectionRequest) => {
      if (!userId) throw new Error('You must be signed in to link an account.');

      const now = new Date().toISOString();
      const value = input.metadataValue.trim();

      if (input.existing) {
        if (isMemberFrozen(input.existing.status)) {
          // Refused before the request rather than after: this update would
          // match zero rows and return 200 with no error, which reads as
          // success to any caller that only inspects `error`.
          throw new Error(
            'This link is ' +
              input.existing.status.replace(/_/g, ' ') +
              '. A member may only change a link that is not connected or rejected, so nothing was sent.'
          );
        }

        const metadata: Record<string, Json> = {
          ...asRecord(input.existing.metadata),
          ...(value ? { [input.metadataKey]: value } : {}),
        };

        const { data, error } = await supabase
          .from('v2_service_connections')
          .update({
            status: 'requested',
            requested_at: now,
            external_reference: value || input.existing.external_reference,
            metadata: metadata as Json,
          })
          .eq('id', input.existing.id)
          .eq('user_id', userId)
          .select('id');

        if (error) throw new Error(error.message);
        if (affectedRows(data) === 0) {
          throw new Error(
            'The request was not recorded. The link may have moved out of a state you are allowed to change since this page loaded.'
          );
        }
        return;
      }

      const { data, error } = await supabase
        .from('v2_service_connections')
        .insert({
          account_id: input.accountId,
          user_id: userId,
          service: input.service,
          status: 'requested',
          requested_at: now,
          external_reference: value || null,
          metadata: (value ? { [input.metadataKey]: value } : {}) as Json,
        })
        .select('id');

      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) throw new Error('The request was not recorded.');
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ik.connections(userId ?? 'anon') });
    },
  });
}

/* ------------------------------------------------------------- admin reads */

/**
 * The review queue.
 *
 * The SELECT policy is `user_id = auth.uid() OR has_role(auth.uid(),'admin')`,
 * so this same query returns only the caller's own rows to a member. The route
 * is role-guarded as well; neither is relied on alone.
 */
export function useReviewQueue(status: string) {
  return useQuery({
    queryKey: ik.queue(status),
    queryFn: async (): Promise<QueueConnection[]> => {
      let q = supabase
        .from('v2_service_connections')
        .select(QUEUE_COLS)
        .order('requested_at', { ascending: true, nullsFirst: false })
        .limit(200);

      if (status === 'open') q = q.in('status', ['requested', 'pending_review']);
      else if (status !== 'all') q = q.eq('status', status);

      return unwrap(await q) ?? [];
    },
  });
}

/* ------------------------------------------------------------ admin writes */

/**
 * Statuses an admin may set from this console.
 *
 * `connected` is absent on purpose. Moving a link to `connected` is a claim
 * that an account exists on the far side, and nothing on this deployment can
 * make that claim — see the disabled approve control on the review screen. The
 * three states here are decisions about our own queue and assert nothing about
 * the property.
 */
export type AdminDecision = 'pending_review' | 'rejected' | 'suspended';

export function useReviewConnection() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      id: string;
      decision: AdminDecision;
      note: string;
      current: ServiceConnection;
    }) => {
      const note = input.note.trim();

      // The note is written; the deciding admin is not. The client could put
      // any uuid in this column and the WITH CHECK would accept it, so a
      // browser-supplied actor would be an attribution nobody could rely on.
      // Attribution needs the server routine named on the review screen.
      const metadata: Record<string, Json> = {
        ...asRecord(input.current.metadata),
        review_note: note || null,
        reviewed_at: new Date().toISOString(),
      };

      const { data, error } = await supabase
        .from('v2_service_connections')
        .update({ status: input.decision, metadata: metadata as Json })
        .eq('id', input.id)
        .select('id');

      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) {
        // The admin UPDATE policy is `has_role(auth.uid(),'admin')` on both
        // USING and WITH CHECK. A caller without the role matches no rows and
        // gets 200 with an empty body — a silent refusal, not an error.
        throw new Error(
          'Nothing was updated. The admin update policy on v2_service_connections matched no rows, which usually means this session does not hold the admin role.'
        );
      }
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ik.all });
    },
  });
}

/* ------------------------------------------------------------- derivations */

export interface ConnectionEvent {
  id: string;
  at: string;
  service: string;
  serviceLabel: string;
  label: string;
  detail: string | null;
  status: string;
}

/**
 * The transitions that can actually be observed on a link row.
 *
 * Nothing records a history of these rows — no trigger, no audit insert — so
 * there is no transition log to read. What the row does carry is four
 * timestamps, and each is evidence of one specific transition having happened:
 * `created_at` that the link was opened, `requested_at` that a request was
 * raised, `connected_at` that it was granted, `updated_at` that something
 * changed last. Those are reported and nothing between them is guessed at — a
 * row that went requested → rejected → requested shows one request, because
 * that is all the row remembers.
 */
export function connectionEvents(connections: ServiceConnection[]): ConnectionEvent[] {
  const events: ConnectionEvent[] = [];

  for (const c of connections) {
    const label = serviceName(c.service);
    const push = (suffix: string, at: string | null, text: string, detail: string | null) => {
      if (!at) return;
      events.push({
        id: c.id + ':' + suffix,
        at,
        service: c.service,
        serviceLabel: label,
        label: text,
        detail,
        status: c.status,
      });
    };

    push('created', c.created_at, 'Link record opened', null);
    push('requested', c.requested_at, 'Connection requested', c.external_reference);
    push('connected', c.connected_at, 'Marked connected', 'Set server-side, not by this browser');

    // Only report "last changed" when it is genuinely a later, distinct moment
    // than the transitions above — otherwise every row gains a duplicate line.
    const known = [c.created_at, c.requested_at, c.connected_at].filter(Boolean) as string[];
    const latestKnown = known.reduce((a, b) => (a > b ? a : b), '');
    if (c.updated_at && c.updated_at > latestKnown) {
      push(
        'updated',
        c.updated_at,
        'Last changed',
        'Now ' + c.status.replace(/_/g, ' ') + '. The row does not record what it changed from.'
      );
    }
  }

  return events.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));
}
