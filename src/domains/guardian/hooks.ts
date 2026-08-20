import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { btcPriceKey, fetchBtcPriceUsd } from '@/lib/btcPrice';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

/**
 * Every read and write the Ares Guardian domain performs.
 *
 * Four rules hold throughout, each of them a direct response to how v2 shipped
 * this surface:
 *
 *  - **Access is never decided in the browser.** v2 put the whole vault behind
 *    `AresGuardianPasswordGate`, one shared string checked by an edge function,
 *    after which the page called itself authorised. Nothing here checks a
 *    password. The domain declares its role requirement and every query relies
 *    on RLS to decide which rows come back.
 *  - **Nothing is provisioned as a side effect of looking.** v2's
 *    `AresGuardian.tsx` inserted five `guardian_wallets` rows for anybody who
 *    typed the password. There is no wallet insert in this file at all.
 *  - **Columns are listed.** No `select('*')`, and `guardian_recovery_keys` is
 *    only ever asked whether a backup exists — `encrypted_words`, `iv` and
 *    `salt` are never requested, so the ciphertext cannot reach the bundle.
 *  - **Funds do not move from here.** The only write that touches a withdrawal
 *    is the member *asking* for one. Approving, completing, rejecting and
 *    cancelling all need a server-side routine that broadcasts the payout and
 *    records the hash the chain returns; none exists, so those controls are
 *    rendered disabled by the pages rather than faked with a table update.
 */

type Tables = Database['public']['Tables'];

export type GuardianWallet = Pick<
  Tables['guardian_wallets']['Row'],
  | 'id'
  | 'asset_symbol'
  | 'asset_name'
  | 'network'
  | 'balance'
  | 'external_balance'
  | 'usd_value'
  | 'wallet_address'
  | 'deposit_address'
  | 'is_active'
  | 'updated_at'
>;

export type GuardianTransaction = Pick<
  Tables['guardian_transactions']['Row'],
  | 'id'
  | 'asset_symbol'
  | 'transaction_type'
  | 'amount'
  | 'usd_value'
  | 'status'
  | 'from_address'
  | 'to_address'
  | 'tx_hash'
  | 'created_at'
>;

export type WithdrawalRequest = Pick<
  Tables['guardian_withdrawal_requests']['Row'],
  | 'id'
  | 'wallet_id'
  | 'user_id'
  | 'asset_symbol'
  | 'network'
  | 'amount'
  | 'destination_address'
  | 'status'
  | 'admin_notes'
  | 'requested_at'
  | 'processed_at'
  | 'window_expires_at'
>;

export type FlashAlert = Pick<
  Tables['guardian_flash_alerts']['Row'],
  | 'id'
  | 'asset_symbol'
  | 'alert_type'
  | 'severity'
  | 'title'
  | 'description'
  | 'trigger_price'
  | 'market_price'
  | 'status'
  | 'action_taken'
  | 'acted_at'
  | 'created_at'
>;

export type MarginSetting = Pick<
  Tables['guardian_margin_settings']['Row'],
  | 'id'
  | 'asset_symbol'
  | 'margin_percent'
  | 'auto_buy_threshold'
  | 'auto_sell_threshold'
  | 'target_markets'
  | 'is_active'
  | 'updated_at'
>;

export type SafeguardWallet = Pick<
  Tables['guardian_safeguard_wallets']['Row'],
  | 'id'
  | 'wallet_name'
  | 'wallet_type'
  | 'asset_symbol'
  | 'network'
  | 'wallet_address'
  | 'balance'
  | 'is_active'
  | 'updated_at'
>;

export type GuardianInvitation = Pick<
  Tables['guardian_invitations']['Row'],
  'id' | 'invited_email' | 'invited_str_domain' | 'status' | 'created_at' | 'expires_at' | 'accepted_at'
>;

/**
 * Query keys, all namespaced under 'guardian'.
 *
 * Invalidating `gk.all` therefore clears the whole domain and cannot miss a
 * consumer, and nothing in this domain shares a key with `src/hooks/data.ts`.
 */
export const gk = {
  all: ['guardian'] as const,
  wallets: ['guardian', 'wallets'] as const,
  transactions: (limit: number) => ['guardian', 'transactions', limit] as const,
  withdrawals: ['guardian', 'withdrawals'] as const,
  alerts: ['guardian', 'alerts'] as const,
  margin: ['guardian', 'margin-settings'] as const,
  safeguards: ['guardian', 'safeguard-wallets'] as const,
  invitations: ['guardian', 'invitations'] as const,
  recoveryKey: (userId: string) => ['guardian', 'recovery-key', userId] as const,
  chainReserves: ['guardian', 'chain-reserves'] as const,
  // The BTC price is not keyed under `guardian`: the risk console reads the
  // same figure, and two keys would let the two pages hold different prices.
  // See lib/btcPrice.ts.
} as const;

/** Throw on a Supabase error so react-query can surface it to an ErrorState. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/* ------------------------------------------------------------------ reads */

/**
 * The vault's asset wallets.
 *
 * Deliberately *not* filtered by `user_id`. The RLS policies on this table are
 * "a member sees their own rows, an operator sees every row", so adding a
 * client-side `user_id` filter would narrow an operator's view to their own
 * (usually empty) holdings and make the console look broken. The server already
 * decides what may be returned; the browser does not need to guess.
 */
export function useGuardianWallets() {
  return useQuery({
    queryKey: gk.wallets,
    queryFn: async (): Promise<GuardianWallet[]> =>
      unwrap(
        await supabase
          .from('guardian_wallets')
          .select(
            'id, asset_symbol, asset_name, network, balance, external_balance, usd_value, wallet_address, deposit_address, is_active, updated_at'
          )
          .eq('is_active', true)
          .order('usd_value', { ascending: false })
      ) ?? [],
  });
}

/** The vault movement log, newest first. */
export function useGuardianTransactions(limit = 15) {
  return useQuery({
    queryKey: gk.transactions(limit),
    queryFn: async (): Promise<GuardianTransaction[]> =>
      unwrap(
        await supabase
          .from('guardian_transactions')
          .select(
            'id, asset_symbol, transaction_type, amount, usd_value, status, from_address, to_address, tx_hash, created_at'
          )
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/** Withdrawal requests visible to the caller. RLS decides whose. */
export function useWithdrawalRequests() {
  return useQuery({
    queryKey: gk.withdrawals,
    queryFn: async (): Promise<WithdrawalRequest[]> =>
      unwrap(
        await supabase
          .from('guardian_withdrawal_requests')
          .select(
            'id, wallet_id, user_id, asset_symbol, network, amount, destination_address, status, admin_notes, requested_at, processed_at, window_expires_at'
          )
          .order('requested_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

export function useFlashAlerts() {
  return useQuery({
    queryKey: gk.alerts,
    queryFn: async (): Promise<FlashAlert[]> =>
      unwrap(
        await supabase
          .from('guardian_flash_alerts')
          .select(
            'id, asset_symbol, alert_type, severity, title, description, trigger_price, market_price, status, action_taken, acted_at, created_at'
          )
          .order('created_at', { ascending: false })
          .limit(50)
      ) ?? [],
  });
}

export function useMarginSettings() {
  return useQuery({
    queryKey: gk.margin,
    queryFn: async (): Promise<MarginSetting[]> =>
      unwrap(
        await supabase
          .from('guardian_margin_settings')
          .select(
            'id, asset_symbol, margin_percent, auto_buy_threshold, auto_sell_threshold, target_markets, is_active, updated_at'
          )
          .order('asset_symbol')
      ) ?? [],
  });
}

/** Cold-storage and reserve wallets, as recorded in the database. */
export function useSafeguardWallets() {
  return useQuery({
    queryKey: gk.safeguards,
    queryFn: async (): Promise<SafeguardWallet[]> =>
      unwrap(
        await supabase
          .from('guardian_safeguard_wallets')
          .select(
            'id, wallet_name, wallet_type, asset_symbol, network, wallet_address, balance, is_active, updated_at'
          )
          .eq('is_active', true)
          .order('wallet_name')
      ) ?? [],
  });
}

export function useGuardianInvitations() {
  return useQuery({
    queryKey: gk.invitations,
    queryFn: async (): Promise<GuardianInvitation[]> =>
      unwrap(
        await supabase
          .from('guardian_invitations')
          .select('id, invited_email, invited_str_domain, status, created_at, expires_at, accepted_at')
          .order('created_at', { ascending: false })
          .limit(50)
      ) ?? [],
  });
}

export interface RecoveryKeyStatus {
  configured: boolean;
  updatedAt: string | null;
}

/**
 * Whether the member has a recovery backup — and nothing else about it.
 *
 * The column list is `id, updated_at` on purpose. `encrypted_words`, `iv` and
 * `salt` are the recovery secret; a screen that only needs to say "backup
 * configured" has no reason to pull the ciphertext and its salt into the
 * browser, where they end up in the react-query cache and in any error report
 * that serialises it.
 */
export function useRecoveryKeyStatus() {
  const userId = useUserId();
  return useQuery({
    queryKey: gk.recoveryKey(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<RecoveryKeyStatus> => {
      const row = unwrap(
        await supabase
          .from('guardian_recovery_keys')
          .select('id, updated_at')
          .eq('user_id', userId!)
          .maybeSingle()
      );
      return { configured: !!row, updatedAt: row?.updated_at ?? null };
    },
  });
}

/* ----------------------------------------------------------- chain reads */

/**
 * One reserve address as the balance service reports it.
 *
 * `balance` is NULL when the chain could not be read for that address. The
 * function used to return 0 in that case, so an unreachable block explorer and
 * an emptied wallet produced the identical page. Null is the only value that
 * distinguishes them, and every consumer here treats it as "unknown", never as
 * "nothing".
 */
export interface ChainWallet {
  address: string;
  balance: number | null;
  balance_satoshi: number | null;
  name: string;
  type: string;
  /** Why the balance is unknown. Null when the read succeeded. */
  error?: string | null;
}

export interface ChainReserves {
  wallets: ChainWallet[];
  totals: {
    /** Null whenever any address failed — a partial sum is not a reserve total. */
    total_btc: number | null;
    total_satoshi: number | null;
    sourceless_btc: number | null;
    ccoin_btc: number | null;
    /** Addresses that answered. */
    active_nodes: number;
    addresses_total?: number;
    addresses_failed?: number;
    last_updated: string;
  };
  success?: boolean;
  error?: string;
}

/** True when at least one reserve address could not be read this refresh. */
export function reservesIncomplete(data: ChainReserves | undefined): boolean {
  if (!data) return false;
  if (data.success === false) return true;
  if ((data.totals.addresses_failed ?? 0) > 0) return true;
  return data.wallets.some((wallet) => wallet.balance === null);
}

const isChainReserves = (value: unknown): value is ChainReserves => {
  if (typeof value !== 'object' || value === null) return false;
  const candidate = value as { wallets?: unknown; totals?: unknown };
  return Array.isArray(candidate.wallets) && typeof candidate.totals === 'object' && candidate.totals !== null;
};

/**
 * On-chain balances of the reserve wallets, straight from `btc-wallet-balances`.
 *
 * What comes back is what is rendered. v2's Proof of Reserve subtracted a list
 * of withdrawal amounts that was hardcoded in the page — with beneficiary
 * names, invoice numbers and transaction hashes typed into the bundle — from
 * the chain figures before displaying them, so the "on-chain" number on screen
 * was one no block explorer would agree with. Committed outflows are read from
 * `guardian_withdrawal_requests` and shown beside the reserve, never folded
 * into it.
 */
export function useChainReserves() {
  return useQuery({
    queryKey: gk.chainReserves,
    // The function walks six addresses against a public explorer; a minute of
    // staleness is cheaper than re-walking them on every focus.
    staleTime: 60_000,
    queryFn: async (): Promise<ChainReserves> => {
      const { data, error } = await supabase.functions.invoke<ChainReserves>('btc-wallet-balances');
      if (error) throw new Error(error.message);
      if (!isChainReserves(data)) {
        throw new Error('btc-wallet-balances returned an unexpected response.');
      }
      return data;
    },
  });
}

/**
 * BTC spot price, used only to annotate BTC figures with an approximate value.
 *
 * The fetch itself lives in `lib/btcPrice.ts` because the risk console needs
 * the same number, and when it had its own `BTC_USD = 118_000` constant the two
 * pages disagreed by 1.84x. A failure returns `null` rather than 0 so the pages
 * can omit the conversion instead of claiming the reserve is worth nothing.
 */
export function useBtcPrice() {
  return useQuery({
    queryKey: btcPriceKey,
    staleTime: 60_000,
    queryFn: fetchBtcPriceUsd,
  });
}

/* -------------------------------------------------------------- mutations */

function useInvalidateGuardian() {
  const qc = useQueryClient();
  return () => {
    void qc.invalidateQueries({ queryKey: gk.all });
  };
}

export interface WithdrawalRequestInput {
  walletId: string;
  assetSymbol: string;
  network: string;
  amount: number;
  destinationAddress: string;
}

/**
 * Ask for a withdrawal.
 *
 * This is the one withdrawal write a client may perform, and it moves nothing:
 * it books a row that an operator then has to action, and RLS
 * (`WITH CHECK (user_id = auth.uid())`) forbids booking it in somebody else's
 * name. `status` and `window_expires_at` are left to their column defaults so
 * the 96-hour window is the server's clock, not the browser's.
 */
export function useRequestWithdrawal() {
  const userId = useUserId();
  const invalidate = useInvalidateGuardian();

  return useMutation({
    mutationFn: async (input: WithdrawalRequestInput) => {
      if (!userId) throw new Error('Your session has expired. Sign in again and retry.');

      const { error } = await supabase.from('guardian_withdrawal_requests').insert({
        user_id: userId,
        wallet_id: input.walletId,
        asset_symbol: input.assetSymbol,
        network: input.network,
        amount: input.amount,
        destination_address: input.destinationAddress,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

export interface AlertDecisionInput {
  alertId: string;
  status: 'acknowledged' | 'resolved';
  actionTaken?: string;
}

/**
 * Record that an operator has seen, or dealt with, a market alert.
 *
 * A direct table update is right here because acknowledging an alert is a note
 * on a log line — no balance changes and no payment is made. It still checks
 * that a row actually came back: the update is only permitted by the operator
 * policy, and PostgREST reports an update that RLS filtered down to zero rows
 * as a success with an empty result. v2 showed a toast on exactly that and left
 * the alert unchanged on screen after the next refresh.
 */
export function useDecideAlert() {
  const userId = useUserId();
  const invalidate = useInvalidateGuardian();

  return useMutation({
    mutationFn: async (input: AlertDecisionInput) => {
      if (!userId) throw new Error('Your session has expired. Sign in again and retry.');

      const { data, error } = await supabase
        .from('guardian_flash_alerts')
        .update({
          status: input.status,
          action_taken: input.actionTaken ?? null,
          acted_by: userId,
          acted_at: new Date().toISOString(),
        })
        .eq('id', input.alertId)
        .select('id');

      if (error) throw new Error(error.message);
      if (!data || data.length === 0) {
        throw new Error('That alert was not updated — you may not have permission to action it.');
      }
    },
    onSuccess: invalidate,
  });
}
