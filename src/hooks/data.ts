import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { qk } from '@/lib/query';
import { positionsFromPools, type EscrowRow, type StakingPool } from '@/lib/balances';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

type Tables = Database['public']['Tables'];
export type V2Account = Tables['v2_accounts']['Row'];
export type V2Claim = Tables['v2_asset_claims']['Row'];
export type V2Asset = Tables['v2_verified_assets']['Row'];
export type Txn = Tables['wallet_transactions']['Row'];

/**
 * Every read in the app goes through one of these.
 *
 * Columns are listed explicitly rather than using select('*') — v2 had 229
 * star-selects, several on wide tables carrying encrypted PII that the UI never
 * displays. Asking for what is rendered keeps payloads small and stops a new
 * sensitive column from silently reaching the browser.
 */

function useUserId() {
  const { user } = useAuth();
  return user?.id ?? null;
}

/** Throw on a Supabase error so react-query can surface it. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

/**
 * The member's token positions.
 *
 * Two reads, not one. Tokens locked in a marketplace escrow have left
 * `user_staking_pools.balance` and are held in `marketplace_escrow_balances`
 * until the sale settles or is cancelled, so a pools-only read reports a
 * seller as poorer than they are the moment they list anything. Reading both
 * here is what makes a sale visible as liquid -> escrowed rather than as a
 * quantity that simply vanishes (F-032).
 */
export function useStakingPools() {
  const userId = useUserId();
  return useQuery({
    queryKey: qk.pools(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const pools = unwrap(
        await supabase
          .from('user_staking_pools')
          .select(
            'id, pool_type, status, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months, lock_end_date, created_at'
          )
          .eq('user_id', userId!)
      );
      const escrow = unwrap(
        await supabase
          .from('marketplace_escrow_balances')
          .select('asset_symbol, amount, status')
          .eq('user_id', userId!)
          .eq('status', 'locked')
      );
      return {
        pools: (pools ?? []) as unknown as StakingPool[],
        escrow: (escrow ?? []) as EscrowRow[],
      };
    },
    select: ({ pools, escrow }) => ({
      pools,
      escrow,
      positions: positionsFromPools(pools, escrow),
    }),
  });
}

export function useTransactions(limit = 10) {
  const userId = useUserId();
  return useQuery({
    queryKey: [...qk.transactions(userId ?? 'anon'), limit],
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('wallet_transactions')
          .select('id, token_type, amount, status, from_user_id, to_user_id, created_at, completed_at')
          .or(`from_user_id.eq.${userId},to_user_id.eq.${userId}`)
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

export function useFiatWallets() {
  const userId = useUserId();
  return useQuery({
    queryKey: qk.fiatWallets(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('fiat_wallets')
          .select('id, currency, balance, available_balance, held_balance')
          .eq('user_id', userId!)
      ) ?? [],
  });
}

export function useIbans() {
  const userId = useUserId();
  return useQuery({
    queryKey: qk.ibans(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('iban_accounts')
          .select('id, iban, bic, currency, balance, status, account_type, is_data_encrypted')
          .eq('user_id', userId!)
      ) ?? [],
  });
}

/** The member's V2 account, its claims and whatever has been verified. */
export function useV2Account() {
  const userId = useUserId();
  return useQuery({
    queryKey: qk.v2Account(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const [account, claims, assets, connections] = await Promise.all([
        supabase
          .from('v2_accounts')
          .select('id, user_id, status, account_mode, email, full_name, country_of_residence, investor_classification, mica_terms_accepted, mica_terms_version, submitted_at, reviewed_at, review_notes, rejection_reason, created_at')
          .eq('user_id', userId!)
          .maybeSingle(),
        supabase
          .from('v2_asset_claims')
          .select('id, account_id, category, asset_symbol, asset_label, claimed_amount, verified_amount, reference, status, review_notes, created_at')
          .eq('user_id', userId!)
          .order('created_at', { ascending: false }),
        supabase
          .from('v2_verified_assets')
          .select('id, category, asset_symbol, asset_label, amount, reference, verified_at')
          .eq('user_id', userId!),
        supabase
          .from('v2_service_connections')
          .select('id, service, status, external_reference, requested_at, connected_at')
          .eq('user_id', userId!),
      ]);

      if (account.error) throw new Error(account.error.message);

      return {
        account: (account.data ?? null) as V2Account | null,
        claims: (claims.data ?? []) as V2Claim[],
        assets: (assets.data ?? []) as V2Asset[],
        connections: connections.data ?? [],
      };
    },
  });
}

/** Submit a new asset claim for verification. */
export function useSubmitClaim() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      accountId: string;
      category: string;
      assetSymbol: string;
      claimedAmount: number;
      reference?: string;
      notes?: string;
    }) => {
      const { error } = await supabase.from('v2_asset_claims').insert({
        account_id: input.accountId,
        user_id: userId!,
        category: input.category,
        asset_symbol: input.assetSymbol,
        claimed_amount: input.claimedAmount,
        reference: input.reference || null,
        notes: input.notes || null,
        status: 'pending',
      });
      // The insert is checked. v2 had 56 unchecked writes, several of which
      // showed a success toast for an operation RLS had silently dropped.
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: qk.v2Account(userId ?? 'anon') }),
  });
}

/**
 * The version string recorded against an acceptance.
 *
 * It must name the terms document the member was actually shown. Existing rows
 * carry 'v2.0' and the operations console renders it verbatim ("Accepted v2.0"),
 * so changing this without publishing a new document would make the record
 * claim something untrue about what was agreed.
 */
export const MICA_TERMS_VERSION = 'v2.0';

/**
 * Accept the MiCA terms.
 *
 * WHY AN UPDATE AND NOT AN RPC: `v2_accounts` already carries an own-update
 * policy (USING status IN ('draft','rejected'), WITH CHECK status IN
 * ('draft','submitted')) and a guard trigger that resets every reviewer field
 * from OLD for a non-admin. So the database already decides exactly what a
 * member may change here, and a SECURITY DEFINER wrapper would only re-state
 * that in a second place where the two could drift.
 *
 * Both writes below `.select('id')` and treat an empty result as a failure.
 * When RLS refuses an UPDATE, PostgREST answers `200 []` — no error, no rows.
 * Reporting that as success is how v2 produced green toasts for operations that
 * did nothing; see F-055.
 */
export function useAcceptTerms() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (accountId: string) => {
      const { data, error } = await supabase
        .from('v2_accounts')
        // No timestamp column here — v2_accounts records the fact and the
        // version only; `mica_terms_accepted_at` lives on user_profiles, which
        // is a different record with its own review flow.
        .update({
          mica_terms_accepted: true,
          mica_terms_version: MICA_TERMS_VERSION,
        })
        .eq('id', accountId)
        .select('id');
      if (error) throw new Error(error.message);
      if (!data || data.length === 0) {
        throw new Error(
          'Terms could not be recorded. An account already submitted or approved can no longer be edited.'
        );
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: qk.v2Account(userId ?? 'anon') }),
  });
}

/**
 * Submit the account for administrator review.
 *
 * Moves status draft/rejected -> submitted, which the own-update policy's WITH
 * CHECK permits and the guard trigger allows for a non-admin. Everything past
 * this point is an administrator's decision.
 */
export function useSubmitForReview() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (accountId: string) => {
      const { data, error } = await supabase
        .from('v2_accounts')
        .update({ status: 'submitted', submitted_at: new Date().toISOString() })
        .eq('id', accountId)
        .select('id');
      if (error) throw new Error(error.message);
      if (!data || data.length === 0) {
        throw new Error('This account is not in a state that can be submitted.');
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: qk.v2Account(userId ?? 'anon') }),
  });
}

/* -------------------------------------------------------------- admin side */

export function useAdminAccounts(status: string) {
  return useQuery({
    queryKey: qk.adminAccounts(status),
    queryFn: async () => {
      let q = supabase
        .from('v2_accounts')
        .select(
          'id, user_id, status, account_mode, email, full_name, country_of_residence, investor_classification, submitted_at, reviewed_at, review_notes, rejection_reason, created_at'
        )
        .order('submitted_at', { ascending: false, nullsFirst: false });

      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

export function useAdminClaims(status: string) {
  return useQuery({
    queryKey: qk.adminClaims(status),
    queryFn: async () => {
      let q = supabase
        .from('v2_asset_claims')
        .select(
          'id, account_id, user_id, category, asset_symbol, asset_label, claimed_amount, verified_amount, status, reference, notes, created_at'
        )
        .order('created_at', { ascending: false });

      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

/**
 * Review an account.
 *
 * Goes through the v2_review_account RPC rather than updating the row directly.
 * The function runs server-side with the authorisation check inside it, so the
 * decision cannot be forged by a client that simply stops calling the guard —
 * which is the failure mode the v2 marketplace code had.
 */
export function useReviewAccount() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { accountId: string; status: string; notes?: string }) => {
      const { error } = await supabase.rpc('v2_review_account', {
        p_account_id: input.accountId,
        p_status: input.status,
        p_notes: input.notes ?? null,
      } as never);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin'] }),
  });
}

export function useReviewClaim() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      claimId: string;
      approve: boolean;
      verifiedAmount?: number;
      notes?: string;
    }) => {
      // The function takes a boolean decision, not a status string.
      const { error } = await supabase.rpc('v2_review_asset_claim', {
        p_claim_id: input.claimId,
        p_approve: input.approve,
        p_verified_amount: input.verifiedAmount ?? null,
        p_notes: input.notes ?? null,
      } as never);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin'] }),
  });
}
