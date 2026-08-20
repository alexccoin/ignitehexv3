import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

/**
 * Governance data access.
 *
 * Every read here is a react-query query and every write is a mutation that
 * invalidates by key. v2's Governance page and ARX portal each held their own
 * useState/useEffect fetch pairs and re-called `loadProposals()` by hand after
 * a write, which is why a vote cast in one tab never showed up in another.
 *
 * Columns are always listed explicitly. Several of these tables carry KYC
 * documents, signing-key hashes and encrypted metadata that no screen renders;
 * select('*') would ship all of it to the browser.
 */

type Tables = Database['public']['Tables'];

export type Proposal = Pick<
  Tables['governance_proposals']['Row'],
  | 'id'
  | 'user_id'
  | 'title'
  | 'description'
  | 'status'
  | 'vote_count'
  | 'support_votes'
  | 'created_at'
  | 'voting_ends_at'
>;

export type ArxMembership = Pick<
  Tables['arx_club_members']['Row'],
  | 'id'
  | 'user_id'
  | 'membership_tier'
  | 'status'
  | 'governance_role'
  | 'council_member'
  | 'executive_board'
  | 'node_operator'
  | 'kyc_status'
  | 'voting_weight'
  | 'joined_at'
  | 'expires_at'
  | 'wnft_credential'
>;

export type ArxApplication = Pick<
  Tables['arx_applications']['Row'],
  | 'id'
  | 'user_id'
  | 'full_name'
  | 'email'
  | 'status'
  | 'application_date'
  | 'nda_accepted_at'
  | 'gdpr_accepted_at'
  | 'charter_accepted_at'
  | 'admin_notes'
  | 'processed_at'
>;

export type ArxBallot = Pick<
  Tables['arx_voting_ballots']['Row'],
  | 'id'
  | 'title'
  | 'description'
  | 'ballot_type'
  | 'status'
  | 'quorum_required'
  | 'voting_start'
  | 'voting_end'
  | 'snapshot_hash'
  | 'published_at'
>;

export type TreasuryPool = Pick<
  Tables['arx_treasury_pools']['Row'],
  | 'id'
  | 'pool_name'
  | 'pool_type'
  | 'status'
  | 'balance_usd'
  | 'balance_arx'
  | 'balance_ars'
  | 'locked_amount'
  | 'multisig_threshold'
  | 'updated_at'
>;

export type TreasuryTransaction = Pick<
  Tables['arx_treasury_transactions']['Row'],
  | 'id'
  | 'pool_id'
  | 'transaction_type'
  | 'amount'
  | 'currency'
  | 'usd_equivalent'
  | 'status'
  | 'required_signatures'
  | 'created_at'
  | 'executed_at'
>;

/** Namespaced by the domain id, so one invalidate clears the whole domain. */
const NS = 'governance';

export const gqk = {
  all: [NS] as const,
  proposals: () => [NS, 'proposals'] as const,
  myVotes: (userId: string) => [NS, 'my-votes', userId] as const,
  membership: (userId: string) => [NS, 'arx-membership', userId] as const,
  arxStats: () => [NS, 'arx-stats'] as const,
  applications: (status: string) => [NS, 'arx-applications', status] as const,
  ballots: () => [NS, 'arx-ballots'] as const,
  myBallotVotes: (userId: string) => [NS, 'arx-ballot-votes', userId] as const,
  events: () => [NS, 'arx-events'] as const,
  auditTrail: () => [NS, 'arx-audit-trail'] as const,
  treasuryPools: () => [NS, 'treasury-pools'] as const,
  treasuryTransactions: () => [NS, 'treasury-transactions'] as const,
} as const;

/** Throw on a Supabase error so react-query can surface it in an ErrorState. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/* -------------------------------------------------------------- proposals */

export function useProposals() {
  return useQuery({
    queryKey: gqk.proposals(),
    queryFn: async (): Promise<Proposal[]> =>
      unwrap(
        await supabase
          .from('governance_proposals')
          .select(
            'id, user_id, title, description, status, vote_count, support_votes, created_at, voting_ends_at'
          )
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

/**
 * The member's own ballot history.
 *
 * Only own rows are read. Tallies come from governance_proposals, which the
 * server maintains: counting votes in the browser would either need every row
 * (which RLS does not hand out) or a read-modify-write of the counters, and two
 * people voting at once would lose one of the votes.
 */
export function useMyVotes() {
  const userId = useUserId();
  return useQuery({
    queryKey: gqk.myVotes(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('governance_votes')
          .select('id, proposal_id, support, voting_power, created_at')
          .eq('user_id', userId!)
      ) ?? [],
    select: (rows) => new Map(rows.map((r) => [r.proposal_id, r])),
  });
}

/** Voting stays open for this long after a proposal is opened. */
const VOTING_WINDOW_HOURS = 72;

export function useCreateProposal() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { title: string; description: string }) => {
      if (!userId) throw new Error('You must be signed in to open a proposal.');
      const endsAt = new Date(Date.now() + VOTING_WINDOW_HOURS * 3_600_000).toISOString();

      const { error } = await supabase.from('governance_proposals').insert({
        user_id: userId,
        title: input.title,
        description: input.description,
        status: 'active',
        // The tallies are columns the server owns. They start empty and are
        // never written from the browser again.
        vote_count: 0,
        support_votes: 0,
        voting_ends_at: endsAt,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: gqk.all }),
  });
}

export function useCastVote() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { proposalId: string; support: boolean }) => {
      if (!userId) throw new Error('You must be signed in to vote.');
      const { error } = await supabase.from('governance_votes').insert({
        user_id: userId,
        proposal_id: input.proposalId,
        support: input.support,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: gqk.all }),
  });
}

/* ---------------------------------------------------------------ARX club */

export function useArxMembership() {
  const userId = useUserId();
  return useQuery({
    queryKey: gqk.membership(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<ArxMembership | null> =>
      unwrap(
        await supabase
          .from('arx_club_members')
          .select(
            'id, user_id, membership_tier, status, governance_role, council_member, executive_board, node_operator, kyc_status, voting_weight, joined_at, expires_at, wnft_credential'
          )
          .eq('user_id', userId!)
          .maybeSingle()
      ),
  });
}

export function useArxStats() {
  return useQuery({
    queryKey: gqk.arxStats(),
    queryFn: async () => {
      // head:true asks for the count only, so no rows cross the wire.
      const [members, council, ballots, events] = await Promise.all([
        supabase
          .from('arx_club_members')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'active'),
        supabase
          .from('arx_club_members')
          .select('id', { count: 'exact', head: true })
          .eq('council_member', true),
        supabase
          .from('arx_voting_ballots')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'active'),
        supabase
          .from('arx_events')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'scheduled')
          .gte('scheduled_at', new Date().toISOString()),
      ]);

      const failure = members.error ?? council.error ?? ballots.error ?? events.error;
      if (failure) throw new Error(failure.message);

      return {
        activeMembers: members.count ?? 0,
        council: council.count ?? 0,
        openBallots: ballots.count ?? 0,
        upcomingEvents: events.count ?? 0,
      };
    },
  });
}

export function useArxApplications(status: string) {
  return useQuery({
    queryKey: gqk.applications(status),
    queryFn: async (): Promise<ArxApplication[]> => {
      let q = supabase
        .from('arx_applications')
        .select(
          'id, user_id, full_name, email, status, application_date, nda_accepted_at, gdpr_accepted_at, charter_accepted_at, admin_notes, processed_at'
        )
        .order('application_date', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

/** The signed-in member's own most recent application, if they made one. */
export function useMyArxApplication() {
  const userId = useUserId();
  return useQuery({
    queryKey: [...gqk.applications('mine'), userId ?? 'anon'],
    enabled: !!userId,
    queryFn: async (): Promise<ArxApplication | null> =>
      unwrap(
        await supabase
          .from('arx_applications')
          .select(
            'id, user_id, full_name, email, status, application_date, nda_accepted_at, gdpr_accepted_at, charter_accepted_at, admin_notes, processed_at'
          )
          .eq('user_id', userId!)
          .order('application_date', { ascending: false })
          .limit(1)
          .maybeSingle()
      ),
  });
}

/**
 * Apply for membership.
 *
 * The row is written by the `submit-arx-application` edge function, which
 * derives email, IP and the acceptance timestamps server-side — the browser
 * cannot backdate its own NDA acceptance. Unlike v2 this sends no geolocation:
 * the form asked the browser for precise coordinates and posted them with the
 * application, which the flow does not need.
 */
export function useSubmitArxApplication() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { fullName: string }) => {
      const { data, error } = await supabase.functions.invoke<{ success?: boolean; error?: string }>(
        'submit-arx-application',
        { body: { full_name: input.fullName } }
      );
      if (error) throw new Error(error.message);
      if (data && data.success === false) {
        throw new Error(data.error ?? 'The application was refused.');
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: gqk.all }),
  });
}

export type ArxDecision = 'approved' | 'declined' | 'blocked' | 'pending';

interface AssignRoleResponse {
  success?: boolean;
  error?: string;
  message?: string;
}

/**
 * Decide an ARX membership application.
 *
 * Approving grants the `arx` role, and that grant is the point of the decision,
 * so it goes through the `assign-role` edge function which verifies the caller
 * is an admin server-side before touching user_roles. v2 inserted into
 * user_roles straight from the browser here (ArxApplicationsManager.tsx, and
 * ArxRoleManager.tsx:88). In v3 user_roles is read-own-only, so a client insert
 * would be rejected regardless.
 *
 * The grant runs first: if it fails the application stays open, which is
 * recoverable. The reverse order would mark someone approved without access.
 */
export function useReviewArxApplication() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      application: ArxApplication;
      decision: ArxDecision;
      notes?: string;
    }) => {
      if (input.decision === 'approved') {
        const { data, error } = await supabase.functions.invoke<AssignRoleResponse>('assign-role', {
          body: { email: input.application.email, role: 'arx' },
        });
        if (error) throw new Error(error.message);
        if (data && data.success === false) {
          throw new Error(data.error ?? 'The role grant was refused.');
        }
      }

      const { error } = await supabase
        .from('arx_applications')
        .update({
          status: input.decision,
          processed_by: userId,
          processed_at: new Date().toISOString(),
          admin_notes: input.notes?.trim() || null,
        })
        .eq('id', input.application.id);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: gqk.all }),
  });
}

export function useArxBallots() {
  return useQuery({
    queryKey: gqk.ballots(),
    queryFn: async (): Promise<ArxBallot[]> =>
      unwrap(
        await supabase
          .from('arx_voting_ballots')
          .select(
            'id, title, description, ballot_type, status, quorum_required, voting_start, voting_end, snapshot_hash, published_at'
          )
          .order('voting_end', { ascending: false })
          .limit(50)
      ) ?? [],
  });
}

export function useMyBallotVotes() {
  const userId = useUserId();
  return useQuery({
    queryKey: gqk.myBallotVotes(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('arx_voting_records')
          .select('id, ballot_id, vote_choice, voting_weight, voted_at')
          .eq('voter_id', userId!)
      ) ?? [],
    select: (rows) => new Map(rows.map((r) => [r.ballot_id, r])),
  });
}

/**
 * Cast a ballot vote.
 *
 * voting_weight is deliberately not sent. It carries a server-side default, so
 * the database decides the weight from the member's registered standing; a
 * browser that supplied its own number could vote with any weight it liked.
 */
export function useCastBallotVote() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { ballotId: string; choice: string }) => {
      if (!userId) throw new Error('You must be signed in to vote.');
      const { error } = await supabase.from('arx_voting_records').insert({
        ballot_id: input.ballotId,
        voter_id: userId,
        vote_choice: input.choice,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: gqk.all }),
  });
}

export function useArxEvents() {
  return useQuery({
    queryKey: gqk.events(),
    queryFn: async () =>
      unwrap(
        await supabase
          .from('arx_events')
          .select(
            'id, event_title, event_type, status, scheduled_at, duration_minutes, location, access_level'
          )
          .gte('scheduled_at', new Date(Date.now() - 24 * 3_600_000).toISOString())
          .order('scheduled_at', { ascending: true })
          .limit(20)
      ) ?? [],
  });
}

/**
 * The attestation feed.
 *
 * v2 rendered three hardcoded fake entries here ("Council Member #1 … 0x7f3d…").
 * This reads the real audit trail and shows an empty state when it is empty,
 * which is the honest answer.
 */
export function useArxAuditTrail(limit = 12) {
  return useQuery({
    queryKey: [...gqk.auditTrail(), limit],
    queryFn: async () =>
      unwrap(
        await supabase
          .from('arx_audit_trail')
          .select(
            'id, action_type, resource_type, resource_id, performed_by, timestamp, attestation_hash'
          )
          .order('timestamp', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/* --------------------------------------------------------------- treasury */

export function useTreasuryPools() {
  return useQuery({
    queryKey: gqk.treasuryPools(),
    queryFn: async (): Promise<TreasuryPool[]> =>
      unwrap(
        await supabase
          .from('arx_treasury_pools')
          .select(
            'id, pool_name, pool_type, status, balance_usd, balance_arx, balance_ars, locked_amount, multisig_threshold, updated_at'
          )
          .order('pool_name', { ascending: true })
      ) ?? [],
  });
}

export function useTreasuryTransactions(limit = 50) {
  return useQuery({
    queryKey: [...gqk.treasuryTransactions(), limit],
    queryFn: async (): Promise<TreasuryTransaction[]> =>
      unwrap(
        await supabase
          .from('arx_treasury_transactions')
          .select(
            'id, pool_id, transaction_type, amount, currency, usd_equivalent, status, required_signatures, created_at, executed_at'
          )
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}
