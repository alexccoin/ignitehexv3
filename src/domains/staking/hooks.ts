import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import { qk } from '@/lib/query';
import { positionsFromPools, type EscrowRow, type StakingPool, type TokenPosition } from '@/lib/balances';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';
import type { LockPeriod, PoolType, RequestFilter } from './constants';

type Tables = Database['public']['Tables'];

/**
 * Every read and write the staking domain performs.
 *
 * Two rules shape this file:
 *
 *  - Staking creates money, so nothing here debits or credits a balance. The
 *    client's only ways to move value are the `submit-staking-request` edge
 *    function (which authenticates the caller and only ever *records a request*)
 *    and the `process_staking_request` / `vesting-rewards-distribution` server
 *    routines, both of which check the caller's role inside the server. v2's
 *    `distribute_enhanced_rewards` RPC minted tokens into `rewards_earned` with
 *    no matching debit and was callable by any signed-in user; it is
 *    deliberately not wrapped by any hook below.
 *
 *  - Columns are listed. `select('*')` on `user_staking_pools` pulls
 *    `admin_notes`, `declined_by` and the enhanced-pool bookkeeping into every
 *    member's browser for no reason.
 */

/* ------------------------------------------------------------------- types */

export type PoolRow = Pick<
  Tables['user_staking_pools']['Row'],
  | 'id'
  | 'pool_type'
  | 'status'
  | 'balance'
  | 'staked_amount'
  | 'rewards_earned'
  | 'apy_rate'
  | 'dynamic_apy'
  | 'stake_duration_months'
  | 'lock_end_date'
  | 'last_reward_date'
  | 'is_enhanced_pool'
  | 'created_at'
>;

export type StakingRequestRow = Pick<
  Tables['staking_requests']['Row'],
  | 'id'
  | 'user_id'
  | 'pool_type'
  | 'request_type'
  | 'amount'
  | 'duration_months'
  | 'status'
  | 'requested_at'
  | 'processed_at'
  | 'admin_notes'
  | 'description'
  | 'domain_name'
  | 'full_name'
  | 'transaction_hash'
  | 'created_at'
>;

export type EnhancedPoolRow = Pick<
  Tables['enhanced_staking_pools']['Row'],
  | 'id'
  | 'name'
  | 'token_type'
  | 'duration_months'
  | 'apr_min'
  | 'apr_max'
  | 'min_stake_amount'
  | 'max_stake_amount'
  | 'tvl_cap'
  | 'status'
  | 'description'
  | 'compounding'
  | 'reward_curve'
>;

export type RewardDistributionRow = Pick<
  Tables['staking_rewards_distribution']['Row'],
  | 'id'
  | 'user_id'
  | 'pool_id'
  | 'stake_amount'
  | 'calculated_apy'
  | 'estimated_reward'
  | 'network_efficiency'
  | 'distribution_date'
  | 'status'
>;

export type RewardActivityRow = Pick<
  Tables['arss_transactions']['Row'],
  'id' | 'amount' | 'currency' | 'description' | 'transaction_type' | 'status' | 'created_at'
>;

export type AggregateStakingStats =
  Database['public']['Functions']['get_aggregate_staking_stats']['Returns'][number];

export type PoolStatus = Database['public']['Enums']['pool_status'];

export interface StakingPortfolio {
  pools: PoolRow[];
  /** Locked marketplace escrow, per asset. Tokens that left `balance`. */
  escrow: EscrowRow[];
  positions: TokenPosition[];
}

/* ---------------------------------------------------------------- plumbing */

/** The domain id doubles as the query-key namespace, so one invalidate clears
 *  everything this domain owns. */
const NS = 'staking';

export const stakingKeys = {
  all: [NS] as const,
  portfolio: (userId: string) => [NS, 'portfolio', userId] as const,
  requests: (userId: string) => [NS, 'requests', userId] as const,
  rewardActivity: (userId: string, days: number) => [NS, 'reward-activity', userId, days] as const,
  aggregate: () => [NS, 'aggregate'] as const,
  poolTemplates: (activeOnly: boolean) => [NS, 'pool-templates', activeOnly] as const,
  apyQuote: (amount: number, months: number) => [NS, 'apy-quote', amount, months] as const,
  unlockable: (poolIds: string[]) => [NS, 'unlockable', poolIds.join(',')] as const,
  payouts: (userId: string) => [NS, 'payouts', userId] as const,
  adminRequests: (status: RequestFilter) => [NS, 'admin', 'requests', status] as const,
  adminDistributions: (limit: number) => [NS, 'admin', 'distributions', limit] as const,
} as const;

/** Throw on a Supabase error so react-query can surface it. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/**
 * A non-2xx edge function response carries the useful message in its body, not
 * in `error.message` (which is only ever "Edge Function returned a non-2xx
 * status code"). v2 surfaced the generic string, so a rejected stake told the
 * user nothing about why.
 */
async function edgeErrorMessage(error: unknown): Promise<string | null> {
  if (error instanceof FunctionsHttpError) {
    try {
      const body: unknown = await error.context.json();
      if (body && typeof body === 'object' && 'error' in body) {
        return String((body as { error: unknown }).error);
      }
    } catch {
      // Body was not JSON. Fall through to the generic message.
    }
  }
  return null;
}

async function invokeEdge<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke<T & { error?: string }>(name, { body });

  if (error) {
    throw new Error((await edgeErrorMessage(error)) ?? error.message);
  }
  // Some of these functions answer 200 with `{ error }` in the body.
  if (data && typeof data === 'object' && typeof data.error === 'string') {
    throw new Error(data.error);
  }
  if (data == null) throw new Error(`${name} returned an empty response.`);
  return data;
}

/* ------------------------------------------------------------ member reads */

/**
 * The member's pools, folded into one position per token.
 *
 * This is a superset of the shell's `useStakingPools` because the domain also
 * renders `dynamic_apy` and `last_reward_date`; the fold itself is delegated to
 * `positionsFromPools` so staked and liquid stay independent numbers.
 */
export function useStakingPortfolio() {
  const userId = useUserId();

  // Escrow is read alongside the pools for the same reason useStakingPools
  // does it (F-032): once a member lists tokens for sale the quantity has left
  // `balance` and lives in marketplace_escrow_balances, and a pools-only read
  // makes it look like it evaporated.
  return useQuery({
    queryKey: stakingKeys.portfolio(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<{ pools: PoolRow[]; escrow: EscrowRow[] }> => {
      const pools =
        unwrap(
          await supabase
            .from('user_staking_pools')
            .select(
              'id, pool_type, status, balance, staked_amount, rewards_earned, apy_rate, dynamic_apy, stake_duration_months, lock_end_date, last_reward_date, is_enhanced_pool, created_at'
            )
            .eq('user_id', userId!)
            .order('created_at', { ascending: false })
        ) ?? [];
      const escrow =
        unwrap(
          await supabase
            .from('marketplace_escrow_balances')
            .select('asset_symbol, amount, status')
            .eq('user_id', userId!)
            .eq('status', 'locked')
        ) ?? [];
      return { pools, escrow: escrow as EscrowRow[] };
    },
    select: ({ pools, escrow }): StakingPortfolio => ({
      pools,
      escrow,
      positions: positionsFromPools(pools as StakingPool[], escrow),
    }),
  });
}

/** The member's own stake/unstake requests. v2 never read this table - its
 *  "Requests History" tab was hardcoded to an empty array. */
export function useMyStakingRequests() {
  const userId = useUserId();

  return useQuery({
    queryKey: stakingKeys.requests(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<StakingRequestRow[]> =>
      unwrap(
        await supabase
          .from('staking_requests')
          .select(
            'id, user_id, pool_type, request_type, amount, duration_months, status, requested_at, processed_at, admin_notes, description, domain_name, full_name, transaction_hash, created_at'
          )
          .eq('user_id', userId!)
          .order('requested_at', { ascending: false, nullsFirst: false })
          .limit(200)
      ) ?? [],
  });
}

/** Reward credits and manual corrections booked against the member. */
export function useRewardActivity(days: number) {
  const userId = useUserId();
  const since = new Date(Date.now() - days * 86_400_000).toISOString();

  return useQuery({
    queryKey: stakingKeys.rewardActivity(userId ?? 'anon', days),
    enabled: !!userId,
    queryFn: async (): Promise<RewardActivityRow[]> =>
      unwrap(
        await supabase
          .from('arss_transactions')
          .select('id, amount, currency, description, transaction_type, status, created_at')
          .eq('user_id', userId!)
          .in('transaction_type', ['staking_reward', 'manual_credit', 'balance_correction'])
          .gte('created_at', since)
          .order('created_at', { ascending: false })
          .limit(500)
      ) ?? [],
  });
}

/** Network-wide totals, computed by the database rather than by summing every
 *  row in the browser as v2 did. */
export function useAggregateStakingStats() {
  return useQuery({
    queryKey: stakingKeys.aggregate(),
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<AggregateStakingStats | null> => {
      const { data, error } = await supabase.rpc('get_aggregate_staking_stats');
      if (error) throw new Error(error.message);
      return data?.[0] ?? null;
    },
  });
}

/** Pool templates. `apr_min`/`apr_max` are the database's advertised range. */
export function usePoolTemplates(activeOnly = true) {
  return useQuery({
    queryKey: stakingKeys.poolTemplates(activeOnly),
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<EnhancedPoolRow[]> => {
      let q = supabase
        .from('enhanced_staking_pools')
        .select(
          'id, name, token_type, duration_months, apr_min, apr_max, min_stake_amount, max_stake_amount, tvl_cap, status, description, compounding, reward_curve'
        )
        .order('token_type', { ascending: true })
        .order('duration_months', { ascending: true });

      if (activeOnly) q = q.eq('status', 'active');
      return unwrap(await q) ?? [];
    },
  });
}

/**
 * The rate the database would apply to this amount over this term.
 *
 * The quote is advisory - the authoritative rate is written by
 * `process_staking_request` when an admin approves - but it comes from the same
 * server-side function rather than from a table shipped in the bundle.
 */
export function useApyQuote(amount: number, durationMonths: number) {
  const valid = Number.isFinite(amount) && amount > 0 && durationMonths > 0;

  return useQuery({
    queryKey: stakingKeys.apyQuote(valid ? amount : 0, durationMonths),
    enabled: valid,
    staleTime: 60_000,
    queryFn: async (): Promise<number | null> => {
      const { data, error } = await supabase.rpc('calculate_dynamic_apy', {
        str_amount: amount,
        duration_months: durationMonths,
      });
      if (error) throw new Error(error.message);
      const n = Number(data);
      return Number.isFinite(n) ? n : null;
    },
  });
}

/**
 * Which FOUNDER POSITIONS the server considers withdrawable.
 *
 * Read the table name and take it literally. `is_withdrawal_available` is:
 *
 *     SELECT lock_end_date, btc_wallet_locked, withdrawal_executed
 *       INTO lock_end, wallet_locked, withdrawal_done
 *       FROM founder_positions
 *      WHERE id = position_id;
 *     RETURN lock_end IS NOT NULL AND now() >= lock_end
 *            AND wallet_locked = true AND withdrawal_done = false;
 *
 * It answers about `founder_positions` and about nothing else. Handed a
 * `user_staking_pools.id` the SELECT matches no row, `lock_end` stays NULL and
 * it returns **false** — not an error, not a null, a confident "no". Confirmed:
 * `select is_withdrawal_available(id), count(*) from user_staking_pools group
 * by 1` → `f | 115`, and `select count(*) from user_staking_pools p join
 * founder_positions f on f.id = p.id` → 0. Asked about a founder position with
 * a past `lock_end_date` the same function returns true.
 *
 * StakingWithdrawals used to call this with pool ids, so every unstake control
 * on that page was permanently disabled. See F-077. The name now says which
 * kind of id it takes so it cannot be misapplied again.
 *
 * TODO(server): staking has no equivalent. It needs an
 * `is_staking_withdrawal_available(p_pool_id uuid)` that reads
 * `user_staking_pools` — lock_end_date, status, and whatever the unstake rules
 * actually are — before a staking screen can put a server answer on screen.
 */
export function useFounderWithdrawalAvailability(poolIds: string[]) {
  const sorted = [...poolIds].sort();

  return useQuery({
    queryKey: stakingKeys.unlockable(sorted),
    enabled: sorted.length > 0,
    queryFn: async (): Promise<Record<string, boolean>> => {
      const results = await Promise.all(
        sorted.map(async (id) => {
          const { data, error } = await supabase.rpc('is_withdrawal_available', {
            position_id: id,
          });
          if (error) throw new Error(error.message);
          return [id, data === true] as const;
        })
      );
      return Object.fromEntries(results);
    },
  });
}

/* ----------------------------------------------------------- member writes */

export interface StakingRequestInput {
  poolType: PoolType;
  requestType: 'stake' | 'unstake';
  amount: number;
  lockPeriod: LockPeriod;
  description?: string;
  /** Required for an external-wallet stake of a token pool. */
  transactionHash?: string | null;
  paymentMethod?: 'external' | 'internal';
  /** Domain stakes only - the edge function rejects the request without them. */
  domainName?: string | null;
  strDomainUsername?: string | null;
  fullName?: string | null;
  strDomainOwned?: string | null;
}

interface SubmitStakingResponse {
  success?: boolean;
  message?: string;
  payment_method?: string;
}

/**
 * Record a stake or unstake request.
 *
 * The client never touches `staking_requests` directly and never adjusts a
 * balance: the edge function authenticates the caller, re-validates every field
 * (including the CCOS internal-payment balance check) and inserts the row under
 * that user's identity. Nothing is credited until an admin approves it through
 * `process_staking_request`.
 */
export function useSubmitStakingRequest() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: StakingRequestInput) =>
      invokeEdge<SubmitStakingResponse>('submit-staking-request', {
        pool_type: input.poolType,
        request_type: input.requestType,
        amount: input.amount,
        lock_period: input.lockPeriod,
        description: input.description?.trim() || '',
        transaction_hash:
          input.paymentMethod === 'internal' ? null : input.transactionHash?.trim() || null,
        domain_name: input.domainName?.trim() || null,
        str_domain_username: input.strDomainUsername?.trim() || null,
        full_name: input.fullName?.trim() || null,
        str_domain_owned: input.strDomainOwned?.trim() || null,
        payment_method: input.paymentMethod ?? 'external',
      }),
    onSuccess: () => {
      const id = userId ?? 'anon';
      void qc.invalidateQueries({ queryKey: stakingKeys.requests(id) });
      void qc.invalidateQueries({ queryKey: stakingKeys.portfolio(id) });
      // The shell's wallet and overview read pools under their own key.
      void qc.invalidateQueries({ queryKey: qk.pools(id) });
      void qc.invalidateQueries({ queryKey: qk.available(id) });
    },
  });
}

/* ------------------------------------------------------------- admin reads */

export function useAdminStakingRequests(status: RequestFilter) {
  return useQuery({
    queryKey: stakingKeys.adminRequests(status),
    queryFn: async (): Promise<StakingRequestRow[]> => {
      let q = supabase
        .from('staking_requests')
        .select(
          'id, user_id, pool_type, request_type, amount, duration_months, status, requested_at, processed_at, admin_notes, description, domain_name, full_name, transaction_hash, created_at'
        )
        .order('requested_at', { ascending: false, nullsFirst: false })
        .limit(200);

      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

/** The audit trail of what the reward routines actually paid out. */
export function useRewardDistributions(limit = 50) {
  return useQuery({
    queryKey: stakingKeys.adminDistributions(limit),
    queryFn: async (): Promise<RewardDistributionRow[]> =>
      unwrap(
        await supabase
          .from('staking_rewards_distribution')
          .select(
            'id, user_id, pool_id, stake_amount, calculated_apy, estimated_reward, network_efficiency, distribution_date, status'
          )
          .order('distribution_date', { ascending: false, nullsFirst: false })
          .limit(limit)
      ) ?? [],
  });
}

/* ------------------------------------------------------------ admin writes */

/**
 * Approve or decline a request.
 *
 * This is the only path by which a staking position comes into existence. The
 * RPC runs with the authorisation check and the APY schedule inside the
 * database: it inserts the `user_staking_pools` row, sets `apy_rate` and
 * `dynamic_apy` from the server-side schedule and stamps the request in one
 * transaction. v2's admin screens did the same thing here, and it is kept - the
 * alternative (inserting the pool row from the browser) would let a client
 * choose its own APY.
 */
export function useProcessStakingRequest() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      requestId: string;
      action: 'approve' | 'decline';
      adminNotes?: string;
    }) => {
      // There are TWO overloads of this function, and picking the wrong one is
      // a privilege escalation:
      //
      //   (p_request_id uuid, p_action text, p_admin_notes text)
      //     SECURITY DEFINER with NO authorization check. This code originally
      //     called it, which let any signed-in member approve their own staking
      //     request and choose its APY — the route's requiresRole guard does
      //     not help, because the RPC is reachable directly over PostgREST.
      //
      //   (request_id uuid, approve boolean, admin_notes_param text)
      //     SECURITY DEFINER that checks the caller is an admin in its body.
      //
      // The argument NAMES select the overload, so this must stay exact. The
      // unguarded one has since had EXECUTE revoked, but the correct target is
      // named here so a future edit cannot silently drift back.
      const { data, error } = await supabase.rpc('process_staking_request', {
        request_id: input.requestId,
        approve: input.action === 'approve',
        admin_notes_param: input.adminNotes?.trim() || undefined,
      });
      if (error) throw new Error(error.message);

      // The function reports refusals in its JSON payload rather than by
      // raising, so a `success: false` must not be read as a success.
      if (data && typeof data === 'object' && !Array.isArray(data)) {
        const result = data as { success?: boolean; error?: string };
        if (result.success === false) {
          throw new Error(result.error ?? 'The request could not be processed.');
        }
      }
      return data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: stakingKeys.all });
    },
  });
}

/**
 * Pause or resume a pool template.
 *
 * `enhanced_staking_pools` is configuration, not ledger: nothing here moves
 * value, so it is a plain checked update rather than an RPC.
 */
export function useSetPoolTemplateStatus() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { poolId: string; status: PoolStatus }) => {
      const { error } = await supabase
        .from('enhanced_staking_pools')
        .update({ status: input.status, updated_at: new Date().toISOString() })
        .eq('id', input.poolId);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: [NS, 'pool-templates'] });
    },
  });
}

export interface PoolTemplateInput {
  /** Omit to create, supply to edit in place. */
  id?: string;
  name: string;
  tokenType: string;
  durationMonths: number;
  aprMin: number;
  aprMax: number;
  minStakeAmount: number | null;
  maxStakeAmount: number | null;
  description: string;
  theme: string;
  compounding: boolean;
  rewardCurve: Database['public']['Enums']['reward_curve'];
}

/**
 * Publish or amend a pool template.
 *
 * This is where the advertised APR range lives. It matters that it is a table
 * an administrator edits and the UI reads back: v2 rendered rates from an
 * `APY_RATES` object compiled into the bundle, so changing a rate meant a
 * deploy, and the shipped values had already drifted from what the database
 * actually paid.
 */
export function useUpsertPoolTemplate() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: PoolTemplateInput) => {
      const payload = {
        name: input.name.trim(),
        token_type: input.tokenType,
        duration_months: input.durationMonths,
        apr_min: input.aprMin,
        apr_max: input.aprMax,
        min_stake_amount: input.minStakeAmount,
        max_stake_amount: input.maxStakeAmount,
        description: input.description.trim() || null,
        theme: input.theme.trim(),
        compounding: input.compounding,
        reward_curve: input.rewardCurve,
        updated_at: new Date().toISOString(),
      };

      const { error } = input.id
        ? await supabase.from('enhanced_staking_pools').update(payload).eq('id', input.id)
        : await supabase
            .from('enhanced_staking_pools')
            .insert({ ...payload, status: 'paused' });

      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: [NS, 'pool-templates'] });
    },
  });
}

interface DistributionResponse {
  success?: boolean;
  processed_pools?: number;
  total_rewards?: number;
  total_rewards_distributed?: number;
  message?: string;
}

/**
 * Run the vesting-aware reward distribution.
 *
 * The edge function verifies the caller holds `admin` against `user_roles` with
 * the service role before doing anything, then delegates the arithmetic and the
 * writes to `distribute_vested_rewards`. Nothing is credited from the browser -
 * the client only asks the server to run, and reads back what it did.
 */
export function useRunRewardDistribution() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async () =>
      invokeEdge<DistributionResponse>('vesting-rewards-distribution', { automated: false }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: stakingKeys.all });
      void qc.invalidateQueries({ queryKey: ['staking-pools'] });
    },
  });
}

/* ------------------------------------------------- external payout requests */

/**
 * The network an external payout leaves on.
 *
 * Taken from `ledger_anchor_chain` (chain_id 2025, name 'SourceLess', native
 * symbol STR) rather than typed in from memory. That row also records
 * `enabled = false` with the reason "Not live … rpc.sourceless.net and
 * explorer.sourceless.net both return NXDOMAIN", which is the second reason a
 * payout here is a request and not a transfer: there is nothing to broadcast to
 * yet, so an operator settles it by hand.
 */
export const PAYOUT_NETWORK = 'SourceLess';

/**
 * Destination addresses this platform issues, and the external form it accepts.
 *
 * `user_profiles.str_wallet_address` is `str_` plus 32 lowercase hex — every
 * one of the 8 sampled rows is exactly 36 characters in that shape. An EVM
 * address is accepted too because a member may be withdrawing to one. This is a
 * typo guard, not authorisation: the operator verifies the destination before
 * anything is sent.
 */
export const PAYOUT_ADDRESS_PATTERN = /^(str_[0-9a-fA-F]{32}|0x[0-9a-fA-F]{40})$/;

export type PayoutRequestRow = Pick<
  Tables['guardian_withdrawal_requests']['Row'],
  | 'id'
  | 'asset_symbol'
  | 'network'
  | 'amount'
  | 'destination_address'
  | 'status'
  | 'admin_notes'
  | 'requested_at'
  | 'window_expires_at'
  | 'processed_at'
>;

/**
 * The member's own external payout requests.
 *
 * `.eq('user_id', …)` is a view filter, not the access control: the table's
 * SELECT policy is already `USING (user_id = auth.uid())`, but administrators
 * hold a second `FOR ALL` policy, and without the filter this member-facing
 * panel would list the whole platform's payouts to anyone who is also staff.
 */
export function useMyPayoutRequests() {
  const userId = useUserId();

  return useQuery({
    queryKey: stakingKeys.payouts(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<PayoutRequestRow[]> =>
      unwrap(
        await supabase
          .from('guardian_withdrawal_requests')
          .select(
            'id, asset_symbol, network, amount, destination_address, status, admin_notes, requested_at, window_expires_at, processed_at'
          )
          .eq('user_id', userId!)
          .order('requested_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

export interface PayoutRequestInput {
  /** Upper-case token symbol. One request is one asset; amounts are never merged. */
  assetSymbol: string;
  amount: number;
  destinationAddress: string;
}

/**
 * Ask for released tokens to be paid out to an external wallet.
 *
 * This books a row and moves nothing, which is the only shape a client is
 * allowed to have here. Three things make it safe to do from the browser, and
 * all three were checked against a live project rather than assumed:
 *
 *  - `WITH CHECK (user_id = auth.uid())` refuses a request booked in somebody
 *    else's name — 403 / 42501, tested.
 *  - There is no member UPDATE or DELETE policy, so a member cannot approve,
 *    complete or withdraw their own request. Both come back `200 []`, tested.
 *  - `status`, `requested_at` and the 96-hour `window_expires_at` are left to
 *    their column defaults, so the clock is the server's and not the browser's.
 *
 * `withdrawal_requests` is deliberately NOT the table used, despite the name.
 * It is the founder-position BTC table, its UPDATE policy is
 * `USING (auth.uid() = user_id)` with no admin policy at all, and a member can
 * therefore set their own row to `approved` and write a `transaction_hash`
 * while no administrator can even read it. Confirmed; see F-074.
 *
 * TODO(server): there is still no database-side check that the amount is
 * covered — a member may ask for more than they hold and the INSERT succeeds.
 * The screen says so plainly rather than implying the figure is enforced. The
 * narrowest fix is a BEFORE INSERT trigger on `guardian_withdrawal_requests`
 * that rejects an amount above the caller's released balance for that asset;
 * the settlement itself needs the payout routine described on the queue.
 */
export function useRequestExternalPayout() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: PayoutRequestInput): Promise<string> => {
      if (!userId) throw new Error('Your session has expired. Sign in again and retry.');

      const destination = input.destinationAddress.trim();
      if (!PAYOUT_ADDRESS_PATTERN.test(destination)) {
        throw new Error('That destination address is not in a form this platform recognises.');
      }
      if (!Number.isFinite(input.amount) || input.amount <= 0) {
        throw new Error('Enter an amount greater than zero.');
      }

      // `.select('id').single()` rather than a bare insert: a write that
      // returned no row did not happen, whatever the absence of an error
      // suggests. This is the F-055 rule applied to the happy path too.
      const { data, error } = await supabase
        .from('guardian_withdrawal_requests')
        .insert({
          user_id: userId,
          asset_symbol: input.assetSymbol,
          network: PAYOUT_NETWORK,
          amount: input.amount,
          destination_address: destination,
        })
        .select('id')
        .single();

      if (error) throw new Error(error.message);
      if (!data) throw new Error('The request was not recorded. Nothing has been sent for review.');
      return data.id;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: stakingKeys.payouts(userId ?? 'anon') });
    },
  });
}
