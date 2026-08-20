import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { qk } from '@/lib/query';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

/**
 * Banking domain data access.
 *
 * Two rules shape every hook below.
 *
 * 1. Columns are listed explicitly. This domain owns the most sensitive tables
 *    in the product — iban_accounts carries encrypted_iban / encrypted_bic /
 *    iban_encryption_iv, and ccoin_bank_applications carries a signed GDPR/NDA
 *    record with the applicant's IP address. None of that is rendered, so none
 *    of it is requested. v2 read both tables with select('*').
 *
 * 2. Nothing here moves money. Card issuance, application approval, top-ups,
 *    swaps and wSTR conversion all go through supabase.functions.invoke, where
 *    the balance arithmetic runs with the service role behind an authorisation
 *    check the browser cannot skip. The only direct writes are two inserts of
 *    an *application* — a request for a product, not a change to a balance.
 */

type Tables = Database['public']['Tables'];

/* --------------------------------------------------------------- utilities */

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
 * Call an edge function and normalise its two failure modes.
 *
 * These functions answer 200 with an `{ error }` body about as often as they
 * answer a non-2xx status, and v2 checked only the transport error — so a
 * refused approval still showed a success toast.
 */
async function invokeFunction<T extends object>(
  name: string,
  body: Record<string, unknown>
): Promise<T> {
  const { data, error } = await supabase.functions.invoke(name, { body });
  if (error) throw new Error(error.message);

  const payload = (data ?? null) as (T & { error?: string }) | null;
  if (payload === null) throw new Error(name + ' returned no response');
  if ('error' in payload && payload.error) throw new Error(String(payload.error));
  return payload;
}

/** Query keys for the domain, namespaced by the domain id. */
export const bankingKeys = {
  all: ['banking'] as const,
  application: (userId: string) => ['banking', 'application', userId] as const,
  profile: (userId: string) => ['banking', 'profile', userId] as const,
  merchantIbans: (userId: string) => ['banking', 'merchant-ibans', userId] as const,
  prepaidCards: (userId: string) => ['banking', 'prepaid-cards', userId] as const,
  networkCard: (userId: string) => ['banking', 'network-card', userId] as const,
  networkTxns: (cardId: string) => ['banking', 'network-transactions', cardId] as const,
  cardApplications: (userId: string) => ['banking', 'card-applications', userId] as const,
  strDomains: (userId: string) => ['banking', 'str-domains', userId] as const,
  fiatTransactions: (userId: string) => ['banking', 'fiat-transactions', userId] as const,
  pendingTransfers: (userId: string) => ['banking', 'pending-transfers', userId] as const,
  crossBorder: (userId: string) => ['banking', 'cross-border', userId] as const,
  ledger: (userId: string) => ['banking', 'ledger', userId] as const,
  adminApplications: (status: string) => ['banking', 'admin', 'applications', status] as const,
  adminCardApplications: (status: string) =>
    ['banking', 'admin', 'card-applications', status] as const,
} as const;

/* ------------------------------------------------------------------- types */

export type BankApplication = Pick<
  Tables['ccoin_bank_applications']['Row'],
  | 'id'
  | 'status'
  | 'full_name'
  | 'email'
  | 'account_type'
  | 'admin_notes'
  | 'created_at'
  | 'processed_at'
>;

export type BankingProfile = Pick<
  Tables['ccoin_banking_profiles']['Row'],
  | 'id'
  | 'banking_status'
  | 'kyc_status'
  | 'full_name'
  | 'email_address'
  | 'str_domain'
  | 'account_type'
  | 'company_name'
  | 'default_iban_country'
  | 'preferred_iban_currencies'
  | 'card_networks_enabled'
  | 'eur_iban_created'
  | 'chf_iban_created'
  | 'gbp_iban_created'
  | 'ccoin_card_created'
  | 'visa_card_created'
  | 'last_banking_sync'
>;

export type PrepaidCard = Pick<
  Tables['prepaid_cards']['Row'],
  | 'id'
  | 'masked_card'
  | 'card_last4'
  | 'card_type'
  | 'currency'
  | 'balance'
  | 'status'
  | 'card_status'
  | 'network'
  | 'issuer'
  | 'physical_card'
  | 'shipping_status'
  | 'expiry_date'
  | 'full_identifier'
  | 'created_at'
>;

export type NetworkCard = Pick<
  Tables['ccoin_network_cards']['Row'],
  'id' | 'card_number' | 'internal_iban' | 'str_domain' | 'status' | 'issued_at' | 'last_activity'
>;

/* ------------------------------------------------------------ member reads */

/**
 * The member's most recent bank application.
 *
 * v2 used .single() here, which throws when a member has never applied — the
 * commonest case on this screen. maybeSingle plus an explicit ordering answers
 * "no application yet" as data rather than as an error.
 */
export function useBankApplication() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.application(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ccoin_bank_applications')
          .select(
            'id, status, full_name, email, account_type, admin_notes, created_at, processed_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle()
      ) as BankApplication | null,
  });
}

export function useBankingProfile() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.profile(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ccoin_banking_profiles')
          .select(
            'id, banking_status, kyc_status, full_name, email_address, str_domain, account_type, company_name, default_iban_country, preferred_iban_currencies, card_networks_enabled, eur_iban_created, chf_iban_created, gbp_iban_created, ccoin_card_created, visa_card_created, last_banking_sync'
          )
          .eq('user_id', userId!)
          .maybeSingle()
      ) as BankingProfile | null,
  });
}

/** Business IBANs held through a merchant account. */
export function useMerchantIbans() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.merchantIbans(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('merchant_business_ibans')
          .select('id, iban, currency, balance, status, account_holder, is_encrypted')
          .eq('user_id', userId!)
      ) ?? [],
  });
}

export function usePrepaidCards() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.prepaidCards(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('prepaid_cards')
          .select(
            'id, masked_card, card_last4, card_type, currency, balance, status, card_status, network, issuer, physical_card, shipping_status, expiry_date, full_identifier, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? []) as PrepaidCard[],
  });
}

export function useNetworkCard() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.networkCard(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ccoin_network_cards')
          .select('id, card_number, internal_iban, str_domain, status, issued_at, last_activity')
          .eq('user_id', userId!)
          .maybeSingle()
      ) as NetworkCard | null,
  });
}

export function useNetworkTransactions(cardId: string | null | undefined, limit = 15) {
  return useQuery({
    queryKey: [...bankingKeys.networkTxns(cardId ?? 'none'), limit],
    enabled: !!cardId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ccoin_network_transactions')
          .select(
            'id, amount, currency, transaction_type, status, from_address, to_address, tx_hash, created_at, completed_at'
          )
          .eq('card_id', cardId!)
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

export function useCardApplications() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.cardApplications(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ccoin_card_applications')
          .select('id, status, str_domain_name, admin_notes, created_at, processed_at')
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

/** STR domains the member holds. A CCoin card is issued against one of them. */
export function useStrDomains() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.strDomains(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('str_domains')
          .select('id, domain_name, status')
          .eq('user_id', userId!)
          .order('domain_name')
      ) ?? [],
  });
}

export function useFiatTransactions(limit = 20) {
  const userId = useUserId();
  return useQuery({
    queryKey: [...bankingKeys.fiatTransactions(userId ?? 'anon'), limit],
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('fiat_transactions')
          .select(
            'id, tx_id, amount, currency, fee, status, transfer_type, from_identifier, to_identifier, requires_approval, created_at, completed_at'
          )
          .or('from_user_id.eq.' + userId + ',to_user_id.eq.' + userId)
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/** Transfers and swaps parked in treasury awaiting an admin decision. */
export function usePendingTreasuryTransfers() {
  const userId = useUserId();
  return useQuery({
    queryKey: bankingKeys.pendingTransfers(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('pending_transfers_treasury')
          .select(
            'id, tx_id, amount, currency, fee_ccos, rail, transfer_type, to_identifier, status, held_until, created_at'
          )
          .eq('from_user_id', userId!)
          .in('status', ['pending', 'held'])
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

export function useCrossBorderPayments(limit = 15) {
  const userId = useUserId();
  return useQuery({
    queryKey: [...bankingKeys.crossBorder(userId ?? 'anon'), limit],
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('cross_border_payments')
          .select(
            'id, amount, currency, fee_amount, payment_rail, status, compliance_score, recipient_name, sender_country, receiver_country, reference, created_at, processed_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/** Settlement entries on the CCoin network ledger. */
export function useLedgerEntries(limit = 15) {
  const userId = useUserId();
  return useQuery({
    queryKey: [...bankingKeys.ledger(userId ?? 'anon'), limit],
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ccoin_ledger')
          .select(
            'id, tx_id, amount, currency, network, status, from_identifier, to_identifier, created_at, validated_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/* ----------------------------------------------------------- member writes */

export interface BankApplicationInput {
  fullName: string;
  email: string;
  signatureFullName: string;
  accountType: 'individual' | 'business';
  companyName?: string;
  companyRegistrationNumber?: string;
}

/**
 * Submit a CCoin Bank application.
 *
 * A direct insert rather than a function call: this creates a *request*. It
 * opens no account and credits nothing — provisioning happens later, in
 * process-ccoin-bank-approval, under an admin's hand.
 *
 * ip_address is NOT NULL with no default and a browser cannot learn its own
 * address, so a placeholder goes in and the real address has to be stamped
 * server-side. See the TODO in the mutation body.
 */
export function useSubmitBankApplication() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: BankApplicationInput) => {
      if (!userId) throw new Error('You must be signed in to apply.');

      const now = new Date().toISOString();
      const { error } = await supabase.from('ccoin_bank_applications').insert({
        user_id: userId,
        full_name: input.fullName,
        email: input.email,
        signature_full_name: input.signatureFullName,
        signature_date: now,
        account_type: input.accountType,
        company_name: input.accountType === 'business' ? input.companyName || null : null,
        company_registration_number:
          input.accountType === 'business' ? input.companyRegistrationNumber || null : null,
        status: 'pending',
        gdpr_accepted: true,
        gdpr_accepted_at: now,
        terms_accepted: true,
        terms_accepted_at: now,
        nda_accepted: true,
        nda_accepted_at: now,
        // TODO(server): ip_address forms part of a signed GDPR/NDA record and
        // must be the real client address. Move this insert behind an edge
        // function that reads x-forwarded-for (or add a database default) and
        // drop the placeholder — a browser cannot supply a trustworthy value.
        ip_address: '0.0.0.0',
        user_agent: navigator.userAgent,
        application_metadata: { submitted_from: 'web_v3' },
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: bankingKeys.application(userId ?? 'anon') }),
  });
}

/** Request a CCoin network card against an STR domain the member holds. */
export function useSubmitCardApplication() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { domainId: string; domainName: string; walletAddress?: string }) => {
      if (!userId) throw new Error('You must be signed in to apply.');

      const { error } = await supabase.from('ccoin_card_applications').insert({
        user_id: userId,
        str_domain_id: input.domainId,
        str_domain_name: input.domainName,
        wallet_address: input.walletAddress || null,
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: bankingKeys.cardApplications(userId ?? 'anon') }),
  });
}

interface SwapResponse {
  to_amount?: number;
  fee?: { fee_ccos?: number };
}

/**
 * Submit a swap. The rate, the CCOS fee and the treasury hold are all decided
 * inside submit-bank-swap; the client only states an intent.
 */
export function useSubmitSwap() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: (input: { fromCurrency: string; toCurrency: string; amount: number }) =>
      invokeFunction<SwapResponse>('submit-bank-swap', {
        from_currency: input.fromCurrency,
        to_currency: input.toCurrency,
        from_amount: input.amount,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: bankingKeys.pendingTransfers(userId ?? 'anon') });
      qc.invalidateQueries({ queryKey: qk.fiatWallets(userId ?? 'anon') });
      qc.invalidateQueries({ queryKey: qk.ibans(userId ?? 'anon') });
    },
  });
}

interface TopUpResponse {
  fee?: { fee_ccos?: number };
}

export function useSubmitCardTopUp() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: (input: {
      sourceIban: string;
      sourceCurrency: string;
      cardIdentifier: string;
      amount: number;
      currency: string;
    }) =>
      invokeFunction<TopUpResponse>('submit-card-topup', {
        source_iban: input.sourceIban,
        source_currency: input.sourceCurrency,
        card_identifier: input.cardIdentifier,
        amount: input.amount,
        currency: input.currency,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: bankingKeys.prepaidCards(userId ?? 'anon') });
      qc.invalidateQueries({ queryKey: bankingKeys.pendingTransfers(userId ?? 'anon') });
      qc.invalidateQueries({ queryKey: qk.ibans(userId ?? 'anon') });
    },
  });
}

interface ConvertResponse {
  fiat_amount?: number;
  currency?: string;
  forex_rate?: number;
}

export function useConvertWstrToFiat() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: (input: { wstrAmount: number; targetCurrency: string }) =>
      invokeFunction<ConvertResponse>('convert-wstr-to-fiat', {
        wstr_amount: input.wstrAmount,
        target_currency: input.targetCurrency,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: qk.fiatWallets(userId ?? 'anon') });
      qc.invalidateQueries({ queryKey: qk.pools(userId ?? 'anon') });
    },
  });
}

/* ------------------------------------------------------------- admin reads */

export function useAdminBankApplications(status: string) {
  return useQuery({
    queryKey: bankingKeys.adminApplications(status),
    queryFn: async () => {
      let q = supabase
        .from('ccoin_bank_applications')
        .select(
          'id, user_id, status, full_name, email, account_type, company_name, admin_notes, created_at, processed_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);

      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

export function useAdminCardApplications(status: string) {
  return useQuery({
    queryKey: bankingKeys.adminCardApplications(status),
    queryFn: async () => {
      let q = supabase
        .from('ccoin_card_applications')
        .select(
          'id, user_id, status, str_domain_name, wallet_address, admin_notes, created_at, processed_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);

      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

/* ------------------------------------------------------------ admin writes */

interface ApprovalResponse {
  already_approved?: boolean;
  ibans_created?: number;
  cards_created?: number;
  products_message?: string;
}

/**
 * Approve a bank application, optionally provisioning IBANs and cards.
 *
 * The function re-derives the admin from the bearer token and calls
 * verify_admin_access itself, so the decision cannot be forged by a client that
 * simply stops rendering the guard.
 */
export function useApproveBankApplication() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: {
      applicationId: string;
      adminNotes?: string;
      autoCreateProducts: boolean;
    }) =>
      invokeFunction<ApprovalResponse>('process-ccoin-bank-approval', {
        application_id: input.applicationId,
        admin_notes: input.adminNotes || null,
        auto_create_products: input.autoCreateProducts,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: bankingKeys.all }),
  });
}

interface IssueCardResponse {
  card?: { card_number?: string };
  magnet_addresses?: unknown[];
}

/** Approve or reject a CCoin card application. Both branches live in the function. */
export function useDecideCardApplication() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: {
      applicationId: string;
      action: 'approve' | 'reject';
      adminNotes?: string;
    }) =>
      invokeFunction<IssueCardResponse>('issue-ccoin-card', {
        applicationId: input.applicationId,
        action: input.action,
        adminNotes: input.adminNotes || null,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: bankingKeys.all }),
  });
}

/** Issue a CCoin network card directly to a member. */
export function useIssueNetworkCard() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { targetUserId: string }) =>
      invokeFunction<IssueCardResponse>('issue-ccoin-network-card', {
        target_user_id: input.targetUserId,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: bankingKeys.all }),
  });
}

export interface ProvisionResult {
  user_id: string;
  full_name: string;
  str_domain: string;
  ibans_created: string[];
  wallets_created: string[];
}

interface ProvisionResponse {
  mode?: string;
  processed?: number;
  results?: ProvisionResult[];
}

/**
 * Bulk-provision IBANs and fiat wallets for approved members.
 *
 * 'preview' is a dry run and is what the UI offers first — this touches every
 * approved member at once and is not something to fire blind.
 */
export function useBulkProvisionBanking() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (input: { mode: 'preview' | 'execute'; limit: number }) =>
      invokeFunction<ProvisionResponse>('bulk-provision-banking', {
        mode: input.mode,
        currencies: ['EUR', 'CHF', 'GBP'],
        limit: input.limit,
        offset: 0,
      }),
    onSuccess: (_data, variables) => {
      if (variables.mode === 'execute') qc.invalidateQueries({ queryKey: bankingKeys.all });
    },
  });
}
