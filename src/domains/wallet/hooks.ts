import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { qk } from '@/lib/query';
import { fetchAvailable } from '@/lib/balances';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';
import { fetchActivity, type ActivityResult } from './ledger';

/**
 * Every read and write the wallet domain performs.
 *
 * Two rules hold throughout and are the reason this file exists at all:
 *
 *  - No balance is ever recomputed in the browser. A figure the user can spend
 *    is either read from `get_available_balance` or produced by a server-side
 *    function. There is no `select balance` → `update balance` anywhere here,
 *    because two of those racing is how money goes missing.
 *  - Every write destructures `{ error }` and throws on it. v2 had 56 writes
 *    that ignored the result and showed a success toast regardless, so an
 *    operation RLS had refused looked identical to one that worked.
 */

type Tables = Database['public']['Tables'];
export type IbanAccount = Pick<
  Tables['iban_accounts']['Row'],
  | 'id'
  | 'iban'
  | 'bic'
  | 'currency'
  | 'balance'
  | 'status'
  | 'account_type'
  | 'account_holder'
  | 'country_code'
  | 'is_data_encrypted'
  | 'created_at'
>;
export type FiatWallet = Pick<
  Tables['fiat_wallets']['Row'],
  'id' | 'currency' | 'balance' | 'available_balance' | 'held_balance' | 'updated_at'
>;
export type HeldTransfer = Pick<
  Tables['pending_transfers_treasury']['Row'],
  'id' | 'tx_id' | 'to_identifier' | 'currency' | 'amount' | 'fee' | 'status' | 'held_until' | 'transfer_type' | 'created_at'
>;

/**
 * Query keys for this domain, namespaced so an invalidate cannot miss one.
 *
 * `ibans` and `fiatWallets` deliberately do NOT reuse `qk.ibans` / `qk.fiatWallets`:
 * `src/hooks/data.ts` already caches those keys with a narrower column list, and
 * two queries sharing a key while selecting different columns means whichever
 * ran first wins and the other silently reads a row missing half its fields.
 * Writes below invalidate both keys so the shared cache stays correct too.
 */
export const wk = {
  all: ['wallet'] as const,
  addresses: (userId: string) => ['wallet', 'addresses', userId] as const,
  activity: (userId: string) => ['wallet', 'activity', userId] as const,
  held: (userId: string) => ['wallet', 'held-transfers', userId] as const,
  ibans: (userId: string) => ['wallet', 'ibans', userId] as const,
  fiatWallets: (userId: string) => ['wallet', 'fiat-wallets', userId] as const,
} as const;

/**
 * Tokens the platform issues a spendable balance for.
 *
 * `get_available_balance` is asked about each one, which is what v2 did — but
 * v2 turned every failure into 0, so a network blip rendered the user's whole
 * holding as locked. Here a failure stays `null` and the UI says so.
 */
export const WALLET_TOKENS = ['str', 'wstr', 'ccos', 'arss', 'estr', 'domain'] as const;

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
 * Spendable balance per token, straight from the server.
 *
 * `null` means "we could not find out", which is deliberately different from
 * `0`. Callers must render the two differently.
 */
export function useAvailableBalances() {
  const userId = useUserId();
  return useQuery({
    queryKey: qk.available(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<Record<string, number | null>> => {
      const results = await Promise.all(
        WALLET_TOKENS.map(async (t) => [t, await fetchAvailable(userId!, t)] as const)
      );
      return Object.fromEntries(results);
    },
  });
}

/** The addresses other members can pay into. */
export function useReceiveAddresses() {
  const userId = useUserId();
  return useQuery({
    queryKey: wk.addresses(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const row = unwrap(
        await supabase
          .from('user_profiles')
          .select('str_domain_owned, str_domain_username, str_wallet_address')
          .eq('user_id', userId!)
          .maybeSingle()
      );
      return {
        strDomain: row?.str_domain_owned ?? null,
        username: row?.str_domain_username ?? null,
        walletAddress: row?.str_wallet_address ?? null,
      };
    },
  });
}

export function useIbanAccounts() {
  const userId = useUserId();
  return useQuery({
    queryKey: wk.ibans(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<IbanAccount[]> =>
      unwrap(
        await supabase
          .from('iban_accounts')
          .select(
            'id, iban, bic, currency, balance, status, account_type, account_holder, country_code, is_data_encrypted, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

export function useFiatWallets() {
  const userId = useUserId();
  return useQuery({
    queryKey: wk.fiatWallets(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<FiatWallet[]> =>
      unwrap(
        await supabase
          .from('fiat_wallets')
          .select('id, currency, balance, available_balance, held_balance, updated_at')
          .eq('user_id', userId!)
          .order('currency')
      ) ?? [],
  });
}

/**
 * Transfers whose funds are sitting in the treasury awaiting a decision.
 *
 * v2 showed these on a separate screen from the wallet, so a member whose money
 * had been held saw only that their balance had dropped.
 */
export function useHeldTransfers() {
  const userId = useUserId();
  return useQuery({
    queryKey: wk.held(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<HeldTransfer[]> =>
      unwrap(
        await supabase
          .from('pending_transfers_treasury')
          .select('id, tx_id, to_identifier, currency, amount, fee, status, held_until, transfer_type, created_at')
          .eq('from_user_id', userId!)
          .eq('status', 'held')
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

/** The unified ledger behind the activity and statement views. */
export function useActivity() {
  const userId = useUserId();
  return useQuery<ActivityResult>({
    queryKey: wk.activity(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: () => fetchActivity(userId!),
  });
}

/* -------------------------------------------------------------- mutations */

/**
 * Call an edge function with the caller's JWT attached.
 *
 * The identity always comes from the token, never from a field in the body —
 * a `user_id` the client chooses is a client that can spend someone else's
 * balance.
 */
async function invokeAsUser<T>(name: string, body: Record<string, unknown>): Promise<T> {
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

/** Everything that could have changed after money moved. */
function useInvalidateWallet() {
  const qc = useQueryClient();
  const userId = useUserId() ?? 'anon';
  return () => {
    void qc.invalidateQueries({ queryKey: wk.all });
    void qc.invalidateQueries({ queryKey: qk.available(userId) });
    void qc.invalidateQueries({ queryKey: qk.pools(userId) });
    void qc.invalidateQueries({ queryKey: qk.transactions(userId) });
    void qc.invalidateQueries({ queryKey: qk.fiatWallets(userId) });
    void qc.invalidateQueries({ queryKey: qk.ibans(userId) });
  };
}

export interface SendTokensInput {
  toAddress: string;
  amount: number;
  tokenType: string;
  /** Only sent when the member has a wallet PIN configured. */
  pin?: string;
}

/**
 * Send tokens to a str.domain or wallet address.
 *
 * The debit happens inside `process-wallet-transaction`, which resolves the
 * recipient, checks the PIN and moves both sides in one transaction. The
 * browser never touches a balance.
 */
export function useSendTokens() {
  const invalidate = useInvalidateWallet();
  return useMutation({
    mutationFn: (input: SendTokensInput) =>
      invokeAsUser<{ message?: string }>('process-wallet-transaction', {
        to_address: input.toAddress,
        amount: input.amount,
        token_type: input.tokenType,
        pin: input.pin || undefined,
      }),
    onSuccess: invalidate,
  });
}

export interface SwapInput {
  fromToken: string;
  toToken: string;
  fromAmount: number;
}

export interface SwapResult {
  from_token: string;
  to_token: string;
  from_amount: number;
  to_amount: number;
  str_price: number;
}

/**
 * Convert between assets.
 *
 * The rate is decided by `process-swap`, not here. v2 computed the quote in the
 * browser from a hardcoded rate table and displayed it as the amount the member
 * would receive, which is a number the server never agreed to.
 */
export function useSwap() {
  const invalidate = useInvalidateWallet();
  return useMutation({
    mutationFn: (input: SwapInput) =>
      invokeAsUser<SwapResult>('process-swap', {
        from_token: input.fromToken,
        to_token: input.toToken,
        from_amount: input.fromAmount,
      }),
    onSuccess: invalidate,
  });
}

export type FiatTransferType = 'network' | 'account' | 'email' | 'sepa' | 'uk_payment' | 'wire' | 'swift';

/** The rails that leave the platform and therefore need bank details. */
export const EXTERNAL_RAILS: readonly FiatTransferType[] = ['sepa', 'uk_payment', 'wire', 'swift'];

export interface FiatTransferInput {
  toIdentifier: string;
  amount: number;
  currency: string;
  transferType: FiatTransferType;
  reference?: string;
  recipientName?: string;
  recipientBankName?: string;
  recipientBankSwift?: string;
}

/**
 * Move fiat.
 *
 * `process-fiat-transfer` debits through `debit_fiat_wallet` and books the
 * `fiat_transactions` row. A transfer to an identifier it cannot resolve comes
 * back as `status: 'held'` with the funds in the treasury — that is a success
 * response, not a failure, and the caller must say so rather than claiming the
 * money arrived.
 */
export function useFiatTransfer() {
  const invalidate = useInvalidateWallet();
  return useMutation({
    mutationFn: (input: FiatTransferInput) =>
      invokeAsUser<{ status?: string; tx_id?: string; message?: string }>('process-fiat-transfer', {
        to_identifier: input.toIdentifier,
        amount: input.amount,
        currency: input.currency,
        transfer_type: input.transferType,
        is_escrow: false,
        auto_swap: false,
        reference: input.reference || undefined,
        recipient_name: input.recipientName || undefined,
        recipient_bank_name: input.recipientBankName || undefined,
        recipient_bank_swift: input.recipientBankSwift || undefined,
      }),
    onSuccess: invalidate,
  });
}

/**
 * Claim back a transfer the treasury is holding.
 *
 * Routed through `request-transfer-refund` rather than calling
 * `refund_held_transfer_atomic` directly: the RPC takes `p_user_id` as an
 * argument, and a client that supplies that argument is a client that can name
 * somebody else. The edge function reads the id from the JWT instead.
 */
export function useRefundHeldTransfer() {
  const invalidate = useInvalidateWallet();
  return useMutation({
    mutationFn: (txId: string) =>
      invokeAsUser<{ refunded_amount?: number; currency?: string; message?: string }>(
        'request-transfer-refund',
        { tx_id: txId }
      ),
    onSuccess: invalidate,
  });
}

/**
 * Route an IBAN's incoming funds into the member's CCoin pool.
 *
 * `link_iban_to_pool` is `SECURITY DEFINER` and takes only the account id, so
 * the caller cannot nominate another member's account.
 */
export function useLinkIbanToPool() {
  const qc = useQueryClient();
  const userId = useUserId() ?? 'anon';
  return useMutation({
    mutationFn: async (input: { ibanId: string; poolType?: string }) => {
      const { data, error } = await supabase.rpc('link_iban_to_pool', {
        iban_id: input.ibanId,
        pool_type_param: input.poolType ?? 'main',
      });
      if (error) throw new Error(error.message);
      if (data === false) throw new Error('The account could not be linked to your pool.');
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: wk.ibans(userId) });
      void qc.invalidateQueries({ queryKey: qk.ibans(userId) });
    },
  });
}
