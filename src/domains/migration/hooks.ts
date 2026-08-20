import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

/**
 * Reads and writes for the migration quarantine.
 *
 * The one thing to hold on to while reading this file: **a quarantined figure
 * is not a balance.** Nothing here feeds the wallet, the ledger or any total
 * the member can spend. It is a claim carried over from the legacy platform,
 * shown so a member knows what was found and an administrator can decide what
 * is true.
 *
 * The database enforces that, not this file. `quarantined_balances` has a
 * SELECT policy and no write policy at all, so every mutation below is an RPC
 * into a SECURITY DEFINER function that checks `is_admin()` itself. A member
 * who calls `approve_migration` from the console gets 42501, and a member who
 * POSTs directly to the table gets the same. See the migration
 * 20260820120000_migration_quarantine.sql for the reasoning.
 */

type Tables = Database['public']['Tables'];
export type MigrationState = Database['public']['Enums']['migration_state'];

export type MigratedAccount = Pick<
  Tables['migrated_accounts']['Row'],
  | 'user_id'
  | 'source_project'
  | 'source_email'
  | 'state'
  | 'imported_at'
  | 'reviewed_at'
  | 'review_notes'
  | 'ledger_journal_id'
>;

export type QuarantinedBalance = Pick<
  Tables['quarantined_balances']['Row'],
  'id' | 'user_id' | 'asset' | 'bucket' | 'source_amount' | 'corrected_amount' | 'note' | 'corrected_at'
>;

/** The columns every read below names. `select('*')` would silently start
 *  returning new columns the UI has never been reviewed against. */
const ACCOUNT_COLS =
  'user_id, source_project, source_email, state, imported_at, reviewed_at, review_notes, ledger_journal_id';
const BALANCE_COLS = 'id, user_id, asset, bucket, source_amount, corrected_amount, note, corrected_at';

/** What an administrator's decision will actually post, per row. */
export function effectiveAmount(b: QuarantinedBalance): number {
  return Number(b.corrected_amount ?? b.source_amount);
}

/* ------------------------------------------------------------------ member */

/**
 * The signed-in member's own migration record, or null if they did not arrive
 * by migration (a locally created account has no row).
 */
export function useMyMigration() {
  const { user } = useAuth();
  return useQuery({
    queryKey: ['migration', 'mine', user?.id],
    enabled: !!user?.id,
    queryFn: async (): Promise<{ account: MigratedAccount; balances: QuarantinedBalance[] } | null> => {
      const { data: account, error } = await supabase
        .from('migrated_accounts')
        .select(ACCOUNT_COLS)
        .eq('user_id', user!.id)
        .maybeSingle();
      if (error) throw error;
      if (!account) return null;

      const { data: balances, error: bErr } = await supabase
        .from('quarantined_balances')
        .select(BALANCE_COLS)
        .eq('user_id', user!.id)
        .order('asset');
      if (bErr) throw bErr;
      return { account, balances: balances ?? [] };
    },
  });
}

/* ------------------------------------------------------------------- admin */

/** Every account awaiting a decision, newest claim first. */
export function useMigrationQueue(state: MigrationState | 'all' = 'all') {
  return useQuery({
    queryKey: ['migration', 'queue', state],
    queryFn: async (): Promise<MigratedAccount[]> => {
      let q = supabase.from('migrated_accounts').select(ACCOUNT_COLS).order('imported_at', { ascending: false });
      if (state !== 'all') q = q.eq('state', state);
      const { data, error } = await q;
      if (error) throw error;
      return data ?? [];
    },
  });
}

/** The claimed figures for one account under review. */
export function useQuarantinedBalances(userId: string | null) {
  return useQuery({
    queryKey: ['migration', 'balances', userId],
    enabled: !!userId,
    queryFn: async (): Promise<QuarantinedBalance[]> => {
      const { data, error } = await supabase
        .from('quarantined_balances')
        .select(BALANCE_COLS)
        .eq('user_id', userId!)
        .order('asset');
      if (error) throw error;
      return data ?? [];
    },
  });
}

function useInvalidate() {
  const qc = useQueryClient();
  return () => {
    void qc.invalidateQueries({ queryKey: ['migration'] });
  };
}

/** Override a claimed figure. Admin only — enforced in the database. */
export function useCorrectBalance() {
  const done = useInvalidate();
  return useMutation({
    mutationFn: async (v: {
      userId: string;
      asset: string;
      bucket: string;
      amount: number;
      note?: string;
    }) => {
      const { error } = await supabase.rpc('set_quarantine_correction', {
        p_user_id: v.userId,
        p_asset: v.asset,
        p_bucket: v.bucket,
        p_amount: v.amount,
        p_note: v.note ?? undefined,
      });
      if (error) throw error;
    },
    onSuccess: done,
  });
}

/**
 * Approve. This is the only path from claim to balance, and it posts a
 * double-entry batch against opening_equity — so the figure that lands in the
 * ledger is traceable to this decision and carries a matching debit.
 */
export function useApproveMigration() {
  const done = useInvalidate();
  return useMutation({
    mutationFn: async (v: { userId: string; note?: string }) => {
      const { data, error } = await supabase.rpc('approve_migration', {
        p_user_id: v.userId,
        p_note: v.note ?? undefined,
      });
      if (error) throw error;
      return data as { ok: boolean; journal_id: string | null; legs: number };
    },
    onSuccess: done,
  });
}

/** Reject. Posts nothing; the claim stays on record with its reason. */
export function useRejectMigration() {
  const done = useInvalidate();
  return useMutation({
    mutationFn: async (v: { userId: string; note: string }) => {
      const { error } = await supabase.rpc('reject_migration', {
        p_user_id: v.userId,
        p_note: v.note,
      });
      if (error) throw error;
    },
    onSuccess: done,
  });
}
