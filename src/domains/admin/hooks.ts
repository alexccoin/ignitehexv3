import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';
import { btcPriceKey, fetchBtcPriceUsd } from '@/lib/btcPrice';
import { ethPriceKey, fetchEthPriceUsd } from '@/lib/ethPrice';
import { buildExposureIndex, MIN_EXPOSURE_USD, type ExposureIndex } from './lib/platformExposure';
import { runPlatformRiskScan, type RiskScanResult } from './lib/platformRiskScan';
import type { MarketRates } from './lib/valuation';
import { assertPushAllowed } from './lib/safeMode';

/**
 * Every read and write the risk console performs.
 *
 * Four rules hold throughout:
 *
 *  1. **No balance is ever computed or written in the browser.** Every figure
 *     shown here is derived from what the tables already say; every change goes
 *     through a `SECURITY DEFINER` server routine that does the arithmetic,
 *     checks authorisation and writes its own audit row. There is no
 *     `select balance` → `update balance` anywhere in this domain. v2's
 *     SuperAdminBalanceAudit did exactly that, from a page with no role check.
 *  2. **Every balance-affecting action is blocked by default.** Safe mode is
 *     armed unless an administrator has typed "PUSH TO BALANCES", and each such
 *     mutation re-checks it inside the mutation via `assertPushAllowed` rather
 *     than trusting a `disabled` button.
 *  3. **Every write destructures `{ error }` and throws on it.** v2 had 56
 *     writes that ignored the result and showed a success toast regardless.
 *  4. **Every read is keyed under `admin`,** so one `invalidateQueries({ queryKey: aqk.all })`
 *     after a correction refreshes the sweep, the scan and the log together —
 *     they are three views of the same numbers and must never disagree.
 */

type Tables = Database['public']['Tables'];

export type VoucherRow = Pick<
  Tables['voucher_redemptions']['Row'],
  | 'id' | 'user_id' | 'full_name' | 'email_address' | 'token_type' | 'package_type'
  | 'status' | 'amount' | 'credited_amount' | 'tokens_credited' | 'payment_hash'
  | 'confirmation_number' | 'proof_of_payment_url' | 'admin_notes' | 'created_at'
  | 'processed_at'
>;

export type CorrectionAction = Pick<
  Tables['v2_admin_actions']['Row'],
  'id' | 'user_id' | 'action' | 'notes' | 'created_at' | 'actor_id' | 'from_status' | 'to_status'
>;

/** Namespaced under the domain id, so one invalidate clears the whole console. */
const NS = 'admin';

export const aqk = {
  all: [NS] as const,
  exposure: (minUsd: number) => [NS, 'exposure', minUsd] as const,
  riskScan: () => [NS, 'risk-scan'] as const,
  corrections: (limit: number) => [NS, 'position-corrections', limit] as const,
  vouchers: (status: string) => [NS, 'voucher-queue', status] as const,
} as const;

function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

function useActorId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/* ------------------------------------------------------------------ reads */

/**
 * The full-database exposure sweep.
 *
 * This reads twenty-odd tables in pages and is expensive, so it is cached for
 * five minutes and does not refetch when the window regains focus — an
 * administrator alt-tabbing should not re-sweep the platform. The header shows
 * when it last ran and offers an explicit re-scan.
 */
export function useExposureIndex(minUsd: number = MIN_EXPOSURE_USD) {
  const rates = useMarketRates();
  return useQuery<ExposureIndex>({
    queryKey: aqk.exposure(minUsd),
    queryFn: async () => buildExposureIndex(minUsd, await rates()),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    refetchOnWindowFocus: false,
  });
}

/** The risk radar. Same cost profile as the sweep, same caching. */
export function useRiskScan() {
  const rates = useMarketRates();
  return useQuery<RiskScanResult>({
    queryKey: aqk.riskScan(),
    queryFn: async () => runPlatformRiskScan(await rates()),
    staleTime: 5 * 60_000,
    gcTime: 15 * 60_000,
    refetchOnWindowFocus: false,
  });
}

/**
 * The market rates both sweeps run on, read through the shared cache.
 *
 * `fetchQuery` on the keys `lib/btcPrice.ts` and `lib/ethPrice.ts` export
 * returns the cache entry when it is fresh and fetches once when it is not, so
 * the exposure sweep, the risk radar and `/guardian/reserves` are all reading
 * literally the same value rather than three fetches that merely tend to agree.
 * That distinction is the whole of F-017: two pages of one application quoted
 * BTC 1.84x apart because each held its own number.
 *
 * A rate that cannot be fetched stays null all the way to the screen and the
 * asset is reported as an unconverted quantity. There is deliberately no
 * fallback constant here — `BTC_USD = 118_000` and `ETH_USD = 3_600` were
 * exactly that, and both were wrong.
 */
function useMarketRates(): () => Promise<MarketRates> {
  const qc = useQueryClient();
  return async () => {
    const [btcUsd, ethUsd] = await Promise.all([
      qc.fetchQuery({ queryKey: btcPriceKey, queryFn: fetchBtcPriceUsd, staleTime: 60_000 }),
      qc.fetchQuery({ queryKey: ethPriceKey, queryFn: fetchEthPriceUsd, staleTime: 60_000 }),
    ]);
    return { btcUsd, ethUsd };
  };
}

/**
 * The position-correction log.
 *
 * `admin_correct_unbacked_positions` writes a `v2_admin_actions` row carrying
 * the exact pre-correction staking, share and vesting values in `before_data`,
 * which is what makes `admin_revert_position_correction` possible. The log is
 * therefore the undo history, not merely a record.
 */
export function useCorrectionLog(limit = 50) {
  return useQuery({
    queryKey: aqk.corrections(limit),
    queryFn: async (): Promise<CorrectionAction[]> =>
      unwrap(
        await supabase
          .from('v2_admin_actions')
          .select('id, user_id, action, notes, created_at, actor_id, from_status, to_status')
          .eq('entity_type', 'position_correction')
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/**
 * The voucher queue, filtered by status.
 *
 * Explicitly capped at 500 and deliberately NOT paginated: this is a review
 * queue an administrator works through, not a total anything is derived from,
 * so a bounded read is correct. The sweeps in `lib/` are the code that must not
 * stop early, and they do not.
 */
export function useVoucherQueue(status: string) {
  return useQuery({
    queryKey: aqk.vouchers(status),
    queryFn: async (): Promise<VoucherRow[]> => {
      let query = supabase
        .from('voucher_redemptions')
        .select(
          'id, user_id, full_name, email_address, token_type, package_type, status, amount, credited_amount, tokens_credited, payment_hash, confirmation_number, proof_of_payment_url, admin_notes, created_at, processed_at'
        )
        .order('created_at', { ascending: false })
        .limit(500);

      if (status !== 'all') query = query.eq('status', status);
      return unwrap(await query) ?? [];
    },
  });
}

/* -------------------------------------------------------------- mutations */

function useInvalidateConsole() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries({ queryKey: aqk.all });
}

/**
 * Quarantine or release one account.
 *
 * A status change moves no money — it stops the member transacting while the
 * exposure is investigated — so it is deliberately NOT behind safe mode. Safe
 * mode blocks pushes to balances; containment must stay available while it is
 * armed, or the console can see a problem and do nothing about it.
 */
export function useSetProfileStatus() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: {
      userId: string;
      status: 'suspended' | 'approved';
      fullName?: string | null;
      email?: string | null;
    }) => {
      const { error } = await supabase.rpc('admin_upsert_user_profile_status', {
        target_user_id: input.userId,
        new_status: input.status,
        full_name: input.fullName ?? undefined,
        email_address: input.email ?? undefined,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

export interface BulkStatusOutcome {
  updated: number;
  failed: number;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function readCount(record: Record<string, unknown> | null, key: string): number {
  const value = record?.[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/**
 * Quarantine or release many accounts in one server-side statement.
 *
 * v2 looped the single-account RPC from the browser, so a bulk quarantine of
 * 300 accounts was 300 round trips that could half-succeed and leave the
 * console showing a state that never existed. One call, one transaction.
 */
export function useBulkProfileStatus() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: {
      userIds: string[];
      status: 'suspended' | 'approved';
      reason?: string;
    }): Promise<BulkStatusOutcome> => {
      if (input.userIds.length === 0) throw new Error('No account selected.');

      const { data, error } = await supabase.rpc('admin_bulk_set_profile_status', {
        target_user_ids: input.userIds,
        new_status: input.status,
        reason: input.reason,
      });
      if (error) throw new Error(error.message);

      const record = asRecord(data);
      return { updated: readCount(record, 'updated'), failed: readCount(record, 'failed') };
    },
    onSuccess: invalidate,
  });
}

export interface CorrectionOutcome {
  scale: number;
  dryRun: boolean;
  raw: Record<string, unknown> | null;
}

/**
 * Scale a member's staking, shares and vesting down to the admin-credited USD.
 *
 * BALANCE-AFFECTING. The scale factor is computed here from figures the sweep
 * already produced, but the arithmetic on the actual balances happens inside
 * `admin_correct_unbacked_positions`, which reads the current rows, writes the
 * originals into `v2_admin_actions.before_data` and only then scales them. The
 * browser never sends a balance.
 *
 * `dryRun` is honoured by the function and is the only variant permitted while
 * safe mode is armed: seeing what a correction would do writes nothing.
 */
export function useCorrectPositions() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: {
      userId: string;
      /** 0..1 — the fraction of the position that admin credit backs. */
      scale: number;
      reason: string;
      dryRun: boolean;
      /** The typed release phrase. Ignored for a dry run. */
      confirmation: string;
    }): Promise<CorrectionOutcome> => {
      if (!input.dryRun) assertPushAllowed(input.confirmation);

      const scale = Math.max(0, Math.min(1, input.scale));
      const { data, error } = await supabase.rpc('admin_correct_unbacked_positions', {
        target_user_id: input.userId,
        scale,
        reason: input.reason,
        dry_run: input.dryRun,
      });
      if (error) throw new Error(error.message);

      return { scale, dryRun: input.dryRun, raw: asRecord(data) };
    },
    onSuccess: invalidate,
  });
}

/**
 * Restore a member's positions to the values recorded before a correction.
 *
 * BALANCE-AFFECTING — it writes balances back up. Same gate as the correction
 * itself: an undo that can be performed more easily than the original action is
 * its own hazard.
 */
export function useRevertCorrection() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: { actionId: string; confirmation: string }) => {
      assertPushAllowed(input.confirmation);
      const { error } = await supabase.rpc('admin_revert_position_correction', {
        action_id: input.actionId,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

/**
 * Approve or reject a voucher.
 *
 * BALANCE-AFFECTING on approval: `process_voucher_redemption_with_audit` credits
 * the member's pools and writes the audit trail in one server-side transaction.
 * Rejection moves nothing, but it runs through the same function so that both
 * outcomes are recorded the same way — v2 updated the row directly for one and
 * called the function for the other, so half the decisions had no audit row.
 */
export function useVoucherDecision() {
  const invalidate = useInvalidateConsole();
  const actorId = useActorId();

  return useMutation({
    mutationFn: async (input: {
      voucherId: string;
      status: 'approved' | 'rejected';
      notes?: string;
      confirmation: string;
    }) => {
      // Crediting is the balance push. Rejection is gated too: it is the same
      // server routine and the same audited decision path.
      assertPushAllowed(input.confirmation);
      if (!actorId) throw new Error('Your session has expired. Sign in again and retry.');

      const { error } = await supabase.rpc('process_voucher_redemption_with_audit', {
        voucher_id: input.voucherId,
        new_status: input.status,
        performed_by_user_id: actorId,
        admin_notes_param: input.notes?.trim() || undefined,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

/**
 * Recompute a voucher's token amount from its package and re-credit the
 * difference.
 *
 * BALANCE-AFFECTING. `admin_correct_voucher_tokens` derives the correct amount
 * server-side from the package type; the browser supplies only the voucher id,
 * so a client cannot nominate the figure it would like credited.
 */
export function useCorrectVoucherTokens() {
  const invalidate = useInvalidateConsole();
  const actorId = useActorId();

  return useMutation({
    mutationFn: async (input: { voucherId: string; confirmation: string }) => {
      assertPushAllowed(input.confirmation);
      if (!actorId) throw new Error('Your session has expired. Sign in again and retry.');

      const { error } = await supabase.rpc('admin_correct_voucher_tokens', {
        voucher_id_param: input.voucherId,
        admin_user_id: actorId,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

/**
 * Set a voucher's credited amount to an explicit figure.
 *
 * BALANCE-AFFECTING, and the only action in the domain where an administrator
 * names an amount. `correct_voucher_amount` books the delta and writes a
 * `voucher_corrections` row holding the previous amount and the difference, so
 * the change is reversible from the record rather than from memory.
 */
export function useCorrectVoucherAmount() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: {
      voucherId: string;
      correctedAmount: number;
      reason: string;
      confirmation: string;
    }) => {
      assertPushAllowed(input.confirmation);
      if (!Number.isFinite(input.correctedAmount) || input.correctedAmount < 0) {
        throw new Error('Enter a corrected amount of zero or more.');
      }

      const { error } = await supabase.rpc('correct_voucher_amount', {
        p_voucher_id: input.voucherId,
        p_corrected_amount: input.correctedAmount,
        p_correction_reason: input.reason.trim() || undefined,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

/** Call an edge function with the caller's JWT attached. */
async function invokeAsAdmin<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw new Error(sessionError.message);

  const token = sessionData.session?.access_token;
  if (!token) throw new Error('Your session has expired. Sign in again and retry.');

  const { data, error } = await supabase.functions.invoke<T & { success?: boolean; error?: string }>(
    name,
    { body, headers: { Authorization: `Bearer ${token}` } }
  );

  if (error) throw new Error(error.message);
  if (!data) throw new Error(`${name} returned no response.`);
  if (data.success === false) throw new Error(data.error ?? `${name} failed.`);
  return data;
}

export interface PrecexCorrectionResult {
  success?: boolean;
  dryRun?: boolean;
  corrected?: number;
  skipped?: number;
  errors?: number;
}

/**
 * Re-credit Pre-CEX STR vouchers to their fixed programme token amounts.
 *
 * The Pre-CEX tiers carry token amounts set by the programme rather than
 * derived from a price, and vouchers redeemed before that was implemented were
 * credited at the $0.005 vesting rate instead. The edge function finds and
 * fixes them server-side.
 *
 * It supports `dryRun`, which is allowed while safe mode is armed — counting
 * what would change writes nothing. A real run is BALANCE-AFFECTING.
 */
export function useCorrectPrecexVouchers() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: { dryRun: boolean; confirmation: string }) => {
      if (!input.dryRun) assertPushAllowed(input.confirmation);
      return invokeAsAdmin<PrecexCorrectionResult>('correct-precex-vouchers', {
        dryRun: input.dryRun,
      });
    },
    onSuccess: invalidate,
  });
}

export interface TargetedCorrectionResult {
  success?: boolean;
  total_vouchers_processed?: number;
  corrected?: number;
  already_correct?: number;
  failed?: number;
}

/**
 * Apply the server's fixed list of targeted $STR voucher corrections.
 *
 * The list of voucher ids and their correct amounts lives inside the edge
 * function, not here — the console cannot choose which vouchers to rewrite or
 * what to rewrite them to. BALANCE-AFFECTING, and it has no dry run, so it is
 * only ever reachable with safe mode released.
 */
export function useCorrectTargetedStrVouchers() {
  const invalidate = useInvalidateConsole();
  return useMutation({
    mutationFn: async (input: { confirmation: string }) => {
      assertPushAllowed(input.confirmation);
      return invokeAsAdmin<TargetedCorrectionResult>('correct-str-vouchers-targeted', {});
    },
    onSuccess: invalidate,
  });
}
