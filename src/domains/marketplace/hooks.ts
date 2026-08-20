import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { qk } from '@/lib/query';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';

/**
 * Data access for the marketplace domain.
 *
 * Two rules shape everything below, and both come from defects in v2:
 *
 *  1. No balance is ever mutated from the browser. v2 escrowed tokens by
 *     reading `user_staking_pools.balance` and writing back the difference
 *     (CreateTokenListingDialog.tsx:186-207, credited back the same way in
 *     UnifiedMarketplaceListings.tsx:180-197). Migration 20260509121934 revoked
 *     user-level INSERT/UPDATE/DELETE on that table, and a PostgREST UPDATE that
 *     RLS filters out answers 204 with `error === null` — so the debit silently
 *     no-opped while the escrow row still inserted, and the seller kept both the
 *     tokens and the listing. The only balance-moving call here is
 *     `marketplace_escrow_lock`, a SECURITY DEFINER wrapper on the ledger
 *     primitive `post_entries`: it re-derives the seller from the listing row
 *     against auth.uid(), posts liquid -> held as one balanced batch under the
 *     account lock, and writes the escrow row and the publication in the same
 *     transaction. It raises on an insufficient balance rather than returning
 *     false (F-032). `debit_staking_pool_balance`, which it replaces, is no
 *     longer executable by `authenticated` at all.
 *
 *  2. Every write checks `error`, and every write whose effect RLS can filter
 *     away also checks that a row actually came back. `error === null` is not
 *     evidence that anything happened.
 */

type Tables = Database['public']['Tables'];

export type DomainListing = Pick<
  Tables['domain_marketplace_listings']['Row'],
  | 'id'
  | 'domain_name'
  | 'domain_type'
  | 'listing_type'
  | 'currency'
  | 'buy_now_price'
  | 'starting_bid'
  | 'reserve_price'
  | 'current_bid'
  | 'current_bidder_id'
  | 'auction_end_at'
  | 'description'
  | 'status'
  | 'seller_id'
  | 'domain_id'
  | 'is_admin_listing'
  | 'views_count'
  | 'created_at'
  | 'reserved_by'
  | 'reservation_expires_at'
  | 'seller_wallet_address'
  | 'seller_wallet_currency'
  | 'seller_eth_wallet'
>;

export type TokenListing = Pick<
  Tables['token_marketplace_listings']['Row'],
  | 'id'
  | 'asset_type'
  | 'asset_symbol'
  | 'amount'
  | 'listing_type'
  | 'price_per_unit'
  | 'total_price'
  | 'starting_bid'
  | 'reserve_price'
  | 'current_bid'
  | 'auction_end_at'
  | 'description'
  | 'status'
  | 'seller_id'
  | 'domain_id'
  | 'views_count'
  | 'created_at'
>;

export type EscrowRow = Pick<
  Tables['marketplace_escrow_balances']['Row'],
  'id' | 'listing_id' | 'user_id' | 'asset_symbol' | 'amount' | 'status' | 'created_at' | 'released_at'
>;

export type Bid = Pick<
  Tables['domain_marketplace_bids']['Row'],
  'id' | 'listing_id' | 'bidder_id' | 'bid_amount' | 'currency' | 'is_winning_bid' | 'status' | 'created_at'
>;

export type MarketTxn = Pick<
  Tables['domain_marketplace_transactions']['Row'],
  | 'id'
  | 'listing_id'
  | 'domain_id'
  | 'buyer_id'
  | 'seller_id'
  | 'sale_price'
  | 'currency'
  | 'sale_type'
  | 'status'
  | 'escrow_status'
  | 'transaction_hash'
  | 'transaction_fee'
  | 'expires_at'
  | 'created_at'
  | 'completed_at'
  | 'released_at'
>;

export type StrDomain = Pick<
  Tables['str_domains']['Row'],
  | 'id'
  | 'domain_name'
  | 'domain_type'
  | 'status'
  | 'is_main_domain'
  | 'domains_count'
  | 'minted_at'
  | 'created_at'
  | 'approved_at'
  | 'is_from_str_dome'
>;

export type DomainConnection = Pick<
  Tables['str_domain_connections']['Row'],
  'id' | 'domain_name' | 'connection_status' | 'last_sync' | 'created_at'
>;

export type DomainNode = Pick<
  Tables['domain_nodes']['Row'],
  'id' | 'domain_id' | 'node_type' | 'node_status' | 'is_active' | 'is_primary' | 'assigned_at' | 'last_sync'
>;

/**
 * Note the absence of `private_key_encrypted`: the UI never renders it, so it
 * never leaves the database. v2's `select('*')` shipped it to every browser.
 */
export type DomainWallet = Pick<
  Tables['domain_wallets']['Row'],
  'id' | 'domain_id' | 'wallet_address' | 'wallet_type' | 'status' | 'public_key' | 'created_at'
>;

export type MerchantAccount = Pick<
  Tables['merchant_accounts']['Row'],
  | 'id'
  | 'merchant_id'
  | 'user_id'
  | 'business_name'
  | 'business_domain_id'
  | 'status'
  | 'payment_processing_enabled'
  | 'webhook_url'
  | 'eur_iban_id'
  | 'usd_iban_id'
  | 'chf_iban_id'
  | 'gbp_iban_id'
  | 'created_at'
>;

export type MerchantProduct = Pick<
  Tables['merchant_products']['Row'],
  | 'id'
  | 'merchant_id'
  | 'product_name'
  | 'description'
  | 'category'
  | 'price'
  | 'price_currency'
  | 'crypto_price'
  | 'crypto_currency'
  | 'stock_quantity'
  | 'is_active'
  | 'is_digital'
  | 'image_url'
  | 'created_at'
>;

export type MerchantIban = Pick<
  Tables['merchant_business_ibans']['Row'],
  | 'id'
  | 'merchant_id'
  | 'currency'
  | 'iban'
  | 'bic'
  | 'account_holder'
  | 'balance'
  | 'status'
  | 'is_encrypted'
  | 'created_at'
>;

export type MerchantApplication = Pick<
  Tables['merchant_account_applications']['Row'],
  | 'id'
  | 'business_name'
  | 'business_domain_id'
  | 'business_description'
  | 'products_services'
  | 'expected_monthly_volume'
  | 'average_transaction_size'
  | 'status'
  | 'admin_notes'
  | 'created_at'
  | 'processed_at'
>;

/* ------------------------------------------------------------------ columns */

const DOMAIN_LISTING_COLS =
  'id, domain_name, domain_type, listing_type, currency, buy_now_price, starting_bid, reserve_price, current_bid, current_bidder_id, auction_end_at, description, status, seller_id, domain_id, is_admin_listing, views_count, created_at, reserved_by, reservation_expires_at, seller_wallet_address, seller_wallet_currency, seller_eth_wallet';

const TOKEN_LISTING_COLS =
  'id, asset_type, asset_symbol, amount, listing_type, price_per_unit, total_price, starting_bid, reserve_price, current_bid, auction_end_at, description, status, seller_id, domain_id, views_count, created_at';

const ESCROW_COLS = 'id, listing_id, user_id, asset_symbol, amount, status, created_at, released_at';

const BID_COLS = 'id, listing_id, bidder_id, bid_amount, currency, is_winning_bid, status, created_at';

const TXN_COLS =
  'id, listing_id, domain_id, buyer_id, seller_id, sale_price, currency, sale_type, status, escrow_status, transaction_hash, transaction_fee, expires_at, created_at, completed_at, released_at';

const STR_DOMAIN_COLS =
  'id, domain_name, domain_type, status, is_main_domain, domains_count, minted_at, created_at, approved_at, is_from_str_dome';

const CONNECTION_COLS = 'id, domain_name, connection_status, last_sync, created_at';
const NODE_COLS = 'id, domain_id, node_type, node_status, is_active, is_primary, assigned_at, last_sync';
const WALLET_COLS = 'id, domain_id, wallet_address, wallet_type, status, public_key, created_at';

const MERCHANT_ACCOUNT_COLS =
  'id, merchant_id, user_id, business_name, business_domain_id, status, payment_processing_enabled, webhook_url, eur_iban_id, usd_iban_id, chf_iban_id, gbp_iban_id, created_at';
const MERCHANT_PRODUCT_COLS =
  'id, merchant_id, product_name, description, category, price, price_currency, crypto_price, crypto_currency, stock_quantity, is_active, is_digital, image_url, created_at';
const MERCHANT_IBAN_COLS =
  'id, merchant_id, currency, iban, bic, account_holder, balance, status, is_encrypted, created_at';
const MERCHANT_APPLICATION_COLS =
  'id, business_name, business_domain_id, business_description, products_services, expected_monthly_volume, average_transaction_size, status, admin_notes, created_at, processed_at';

/* --------------------------------------------------------------- query keys */

/** Namespaced under the domain id, so one invalidate clears the whole domain. */
export const mqk = {
  strDomeRequests: (uid: string) => ['marketplace', 'str-dome-requests', uid] as const,
  all: ['marketplace'] as const,
  domainListings: (scope: string) => ['marketplace', 'domain-listings', scope] as const,
  tokenListings: (scope: string) => ['marketplace', 'token-listings', scope] as const,
  escrow: (userId: string) => ['marketplace', 'escrow', userId] as const,
  bids: (scope: string) => ['marketplace', 'bids', scope] as const,
  txns: (userId: string) => ['marketplace', 'transactions', userId] as const,
  strDomains: (userId: string) => ['marketplace', 'str-domains', userId] as const,
  domainInfra: (userId: string) => ['marketplace', 'domain-infra', userId] as const,
  merchant: (userId: string) => ['marketplace', 'merchant', userId] as const,
  merchantProducts: (merchantRowId: string) => ['marketplace', 'merchant-products', merchantRowId] as const,
  stats: () => ['marketplace', 'stats'] as const,
  availability: (name: string) => ['marketplace', 'domain-available', name] as const,
} as const;

/* ----------------------------------------------------------------- helpers */

function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

export function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/**
 * A write that RLS can filter away must prove it touched something.
 *
 * PostgREST answers an UPDATE or DELETE matching no visible row with a success
 * and an empty body. v2 read that as "it worked" in 56 places.
 */
function affectedRows(rows: unknown[] | null): number {
  return rows?.length ?? 0;
}

/* ------------------------------------------------------------------- reads */

export type ListingScope = 'active' | 'mine';

export function useDomainListings(scope: ListingScope, domainType?: string) {
  const userId = useUserId();
  const key = scope === 'mine' ? `mine:${userId ?? 'anon'}` : `active:${domainType ?? 'all'}`;

  return useQuery({
    queryKey: mqk.domainListings(key),
    enabled: scope === 'active' || !!userId,
    queryFn: async () => {
      let q = supabase.from('domain_marketplace_listings').select(DOMAIN_LISTING_COLS);
      if (scope === 'mine') q = q.eq('seller_id', userId!);
      else q = q.eq('status', 'active');
      if (domainType && domainType !== 'all') q = q.eq('domain_type', domainType);
      return (unwrap(await q.order('created_at', { ascending: false }).limit(200)) ??
        []) satisfies DomainListing[];
    },
  });
}

export function useTokenListings(scope: ListingScope) {
  const userId = useUserId();
  const key = scope === 'mine' ? `mine:${userId ?? 'anon'}` : 'active';

  return useQuery({
    queryKey: mqk.tokenListings(key),
    enabled: scope === 'active' || !!userId,
    queryFn: async () => {
      let q = supabase.from('token_marketplace_listings').select(TOKEN_LISTING_COLS);
      if (scope === 'mine') q = q.eq('seller_id', userId!);
      else q = q.eq('status', 'active');
      return (unwrap(await q.order('created_at', { ascending: false }).limit(200)) ??
        []) satisfies TokenListing[];
    },
  });
}

/** What the member currently has locked against a listing. */
export function useMyEscrow() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.escrow(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('marketplace_escrow_balances')
          .select(ESCROW_COLS)
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? []) satisfies EscrowRow[],
  });
}

export function useMyBids() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.bids(`mine:${userId ?? 'anon'}`),
    enabled: !!userId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('domain_marketplace_bids')
          .select(BID_COLS)
          .eq('bidder_id', userId!)
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? []) satisfies Bid[],
  });
}

/** Bids on one listing. Only the seller can normally read these; RLS decides. */
export function useListingBids(listingId: string | null) {
  return useQuery({
    queryKey: mqk.bids(`listing:${listingId ?? 'none'}`),
    enabled: !!listingId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('domain_marketplace_bids')
          .select(BID_COLS)
          .eq('listing_id', listingId!)
          .order('bid_amount', { ascending: false })
      ) ?? []) satisfies Bid[],
  });
}

export function useMyTransactions() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.txns(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('domain_marketplace_transactions')
          .select(TXN_COLS)
          .or(`buyer_id.eq.${userId},seller_id.eq.${userId}`)
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? []) satisfies MarketTxn[],
  });
}

export function useMyDomains() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.strDomains(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('str_domains')
          .select(STR_DOMAIN_COLS)
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? []) satisfies StrDomain[],
  });
}

/** Connections, nodes and wallets together — they are always shown together. */
export function useDomainInfrastructure() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.domainInfra(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const [connections, nodes, wallets] = await Promise.all([
        supabase.from('str_domain_connections').select(CONNECTION_COLS).eq('user_id', userId!),
        supabase.from('domain_nodes').select(NODE_COLS).eq('user_id', userId!),
        supabase.from('domain_wallets').select(WALLET_COLS).eq('user_id', userId!),
      ]);
      // Each leg is checked. A partial failure is an error, not an empty list —
      // v2 rendered "no nodes" for a request the server had actually rejected.
      if (connections.error) throw new Error(connections.error.message);
      if (nodes.error) throw new Error(nodes.error.message);
      if (wallets.error) throw new Error(wallets.error.message);
      return {
        connections: (connections.data ?? []) satisfies DomainConnection[],
        nodes: (nodes.data ?? []) satisfies DomainNode[],
        wallets: (wallets.data ?? []) satisfies DomainWallet[],
      };
    },
  });
}

export function useMerchant() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.merchant(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const [account, application] = await Promise.all([
        supabase
          .from('merchant_accounts')
          .select(MERCHANT_ACCOUNT_COLS)
          .eq('user_id', userId!)
          .maybeSingle(),
        supabase
          .from('merchant_account_applications')
          .select(MERCHANT_APPLICATION_COLS)
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
      ]);
      if (account.error) throw new Error(account.error.message);
      if (application.error) throw new Error(application.error.message);

      const acct = (account.data ?? null) satisfies MerchantAccount | null;

      // The child tables key on merchant_accounts.id (the uuid PK), not on the
      // human-readable merchant_id string. v2 mixed the two up between files.
      let ibans: MerchantIban[] = [];
      if (acct) {
        const res = await supabase
          .from('merchant_business_ibans')
          .select(MERCHANT_IBAN_COLS)
          .eq('merchant_id', acct.id)
          .order('currency');
        if (res.error) throw new Error(res.error.message);
        ibans = (res.data ?? []) satisfies MerchantIban[];
      }

      return {
        account: acct,
        application: (application.data ?? null) satisfies MerchantApplication | null,
        ibans,
      };
    },
  });
}

export function useMerchantProducts(merchantRowId: string | null) {
  return useQuery({
    queryKey: mqk.merchantProducts(merchantRowId ?? 'none'),
    enabled: !!merchantRowId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('merchant_products')
          .select(MERCHANT_PRODUCT_COLS)
          .eq('merchant_id', merchantRowId!)
          .order('created_at', { ascending: false })
      ) ?? []) satisfies MerchantProduct[],
  });
}

/** Headline counts. Counted server-side rather than by fetching every row. */
export function useMarketplaceStats() {
  return useQuery({
    queryKey: mqk.stats(),
    queryFn: async () => {
      const [domains, tokens] = await Promise.all([
        supabase
          .from('domain_marketplace_listings')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'active'),
        supabase
          .from('token_marketplace_listings')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'active'),
      ]);
      if (domains.error) throw new Error(domains.error.message);
      if (tokens.error) throw new Error(tokens.error.message);
      return { domainListings: domains.count ?? 0, tokenListings: tokens.count ?? 0 };
    },
  });
}

/** Availability is decided by the server, never guessed by the client. */
export function useDomainAvailability(name: string) {
  const trimmed = name.trim().toLowerCase();
  return useQuery({
    queryKey: mqk.availability(trimmed),
    enabled: /^[a-z0-9-]{3,32}$/.test(trimmed),
    staleTime: 0,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('is_domain_available_for_listing', {
        p_domain_name: trimmed,
      });
      if (error) throw new Error(error.message);
      return data === true;
    },
  });
}

/* ---------------------------------------------------------------- mutations */

/**
 * Listing a domain moves no balance — the domain stays with its owner until a
 * settled sale, so one checked insert is the whole operation.
 */
export function useCreateDomainListing() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      domainId: string;
      domainName: string;
      domainType: string;
      listingType: 'buy_now' | 'auction';
      currency: string;
      buyNowPrice: number | null;
      startingBid: number | null;
      reservePrice: number | null;
      auctionDays: number | null;
      description: string | null;
      payoutAddress: string | null;
    }) => {
      const { error } = await supabase.from('domain_marketplace_listings').insert({
        seller_id: userId!,
        domain_id: input.domainId,
        domain_name: input.domainName,
        domain_type: input.domainType,
        listing_type: input.listingType,
        currency: input.currency,
        buy_now_price: input.buyNowPrice,
        starting_bid: input.startingBid,
        reserve_price: input.reservePrice,
        auction_end_at:
          input.listingType === 'auction' && input.auctionDays
            ? new Date(Date.now() + input.auctionDays * 86_400_000).toISOString()
            : null,
        description: input.description,
        // Only a real address is stored. v2 fell back to a hardcoded admin
        // wallet constant, quietly redirecting the buyer's payment.
        seller_wallet_address: input.payoutAddress,
        seller_wallet_currency: input.payoutAddress ? input.currency : null,
        status: 'active',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/** Withdrawing a domain listing releases nothing but the advert. */
export function useCancelDomainListing() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (listingId: string) => {
      const { data, error } = await supabase
        .from('domain_marketplace_listings')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('id', listingId)
        .eq('seller_id', userId!)
        .eq('status', 'active')
        .select('id');
      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) {
        throw new Error(
          'The listing was not cancelled — it may already be reserved by a buyer, sold, or not yours to cancel.'
        );
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/**
 * Raised when money moved but the record of it did not. Never swallowed.
 *
 * Kept exported and kept caught by the Sell page. It is no longer REACHABLE
 * from the token sell path: `marketplace_escrow_lock` posts the transfer,
 * writes the escrow row and publishes the listing in one transaction, so
 * "debited but not recorded" cannot occur there any more (F-032). It stays
 * because the state it names is a real one — any future path that moves value
 * and its record in two steps can still produce it, and a class that exists is
 * cheaper than one that has to be reinvented.
 */
export class EscrowInconsistencyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EscrowInconsistencyError';
  }
}

/**
 * `marketplace_escrow_lock(p_listing_id)`.
 *
 * Hand-typed because src/lib/database.types.ts is generated from the schema as
 * it stood before 20260819140000 and does not yet carry the ledger functions.
 * The cast is confined to this one function so no caller has to write `as
 * never` at a call site, which is where an untyped argument would actually
 * hurt.
 */
interface EscrowLockResult {
  locked: boolean;
  listing_id: string;
  asset: string;
  amount: number;
}

async function escrowLock(
  listingId: string
): Promise<{ data: EscrowLockResult | null; error: { message: string } | null }> {
  // `.bind(supabase)`, not a bare extraction: `const rpc = supabase.rpc` loses
  // `this` and throws at call time.
  const rpc = supabase.rpc.bind(supabase) as unknown as (
    fn: string,
    args: Record<string, unknown>
  ) => PromiseLike<{ data: EscrowLockResult | null; error: { message: string } | null }>;
  return rpc('marketplace_escrow_lock', { p_listing_id: listingId });
}

/**
 * List tokens for sale, moving them into escrow.
 *
 * TWO steps now, not four (F-032).
 *
 *   1. insert the listing as `pending_escrow` — invisible to buyers, no money;
 *   2. `marketplace_escrow_lock(listing_id)` — one server transaction that
 *      posts the tokens from the seller's `liquid` bucket to their `held`
 *      bucket through `post_entries`, writes the escrow row and publishes the
 *      listing. All or nothing.
 *
 * What this replaces, and why it had to:
 *
 * The old flow called `debit_staking_pool_balance`, then inserted the escrow
 * row, then published — three separate transactions after the draft. The debit
 * is a ONE-WAY move: it takes value out of `user_staking_pools.balance` and
 * gives it to nothing. There is no account it went to, so nothing could put it
 * back (Sell.tsx still disables Cancel for exactly that reason) and nothing
 * could reconcile against it. That also made two states reachable that should
 * not exist: debited-with-no-escrow-row, and escrowed-but-unpublished. The
 * first was raised as an EscrowInconsistencyError precisely because there was
 * no way to compensate it.
 *
 * `marketplace_escrow_lock` is the inverse of `release_marketplace_escrow`,
 * which already existed. Both legs of the transfer are posted in one balanced
 * batch, so an insufficient balance is refused under the account lock with the
 * amount named, and neither intermediate state is reachable. Cancelling a
 * listing becomes possible for the first time.
 *
 * A failure still leaves only the invisible draft from step 1, which is
 * deleted the same way it always was.
 */
export function useCreateTokenListing() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      symbol: string;
      amount: number;
      listingType: 'buy_now' | 'auction';
      pricePerUnit: number | null;
      startingBid: number | null;
      reservePrice: number | null;
      auctionDays: number | null;
      description: string | null;
    }) => {
      if (!userId) throw new Error('You must be signed in to create a listing.');
      if (!(input.amount > 0)) throw new Error('Enter an amount greater than zero.');

      const symbol = input.symbol.toUpperCase();
      const totalPrice =
        input.pricePerUnit !== null ? Number((input.pricePerUnit * input.amount).toFixed(2)) : null;

      // 1. The advert, parked out of sight until the tokens are actually locked.
      const created = await supabase
        .from('token_marketplace_listings')
        .insert({
          seller_id: userId,
          asset_type: 'token',
          asset_symbol: symbol,
          amount: input.amount,
          listing_type: input.listingType,
          price_per_unit: input.pricePerUnit,
          total_price: totalPrice,
          starting_bid: input.startingBid,
          reserve_price: input.reservePrice,
          auction_end_at:
            input.listingType === 'auction' && input.auctionDays
              ? new Date(Date.now() + input.auctionDays * 86_400_000).toISOString()
              : null,
          description: input.description,
          status: 'pending_escrow',
        })
        .select('id')
        .single();

      if (created.error) throw new Error(created.error.message);
      const listingId = created.data.id;

      // 2. Lock, record and publish — one server transaction. It raises on an
      //    insufficient balance rather than returning a boolean, so there is no
      //    "returned false and I forgot to check" path.
      const locked = await escrowLock(listingId);

      if (locked.error || locked.data?.locked !== true) {
        // Nothing was taken — the whole RPC rolled back — so nothing may be
        // left advertised.
        const cleanup = await supabase
          .from('token_marketplace_listings')
          .delete()
          .eq('id', listingId)
          .eq('seller_id', userId)
          .select('id');

        const reason = locked.error
          ? `The escrow lock was refused: ${locked.error.message}`
          : `The escrow lock for ${input.amount} ${symbol} did not apply.`;

        if (cleanup.error || affectedRows(cleanup.data) === 0) {
          throw new Error(
            `${reason} The draft listing ${listingId} could not be removed and is still held as pending_escrow — nothing was debited.`
          );
        }
        throw new Error(reason);
      }

      return { listingId };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: mqk.all });
      // Liquid balance fell and escrow rose, so the wallet, the staking pages
      // and the dashboard must all refetch.
      if (userId) {
        qc.invalidateQueries({ queryKey: qk.pools(userId) });
        qc.invalidateQueries({ queryKey: qk.available(userId) });
        qc.invalidateQueries({ queryKey: ['staking'] });
      }
    },
  });
}

/**
 * Reserve a domain listing ahead of an off-platform payment.
 *
 * No balance moves: this claims the listing and opens a pending order the
 * seller settles. The step order is the reverse of v2's, deliberately.
 *
 * v2 inserted the transaction first, then updated the listing without checking
 * anything (BuyNowDialog.tsx:158-183), and toasted "Domain reserved for 6
 * hours!" unconditionally at :176. A buyer has no write access to another
 * member's listing row, so the reservation routinely did nothing and left an
 * orphan pending transaction behind. Here the contended row is claimed first,
 * guarded on `status = 'active'` so two buyers cannot both win it, and the claim
 * is only believed if a row comes back. If the order then fails to insert, the
 * reservation is released again.
 */
export function useReserveListing() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { listing: DomainListing; hours: number }) => {
      if (!userId) throw new Error('You must be signed in to reserve a listing.');
      const { listing } = input;
      if (listing.buy_now_price === null) throw new Error('This listing has no buy-now price.');

      const expiresAt = new Date(Date.now() + input.hours * 3_600_000).toISOString();

      const claim = await supabase
        .from('domain_marketplace_listings')
        .update({
          status: 'reserved',
          reserved_at: new Date().toISOString(),
          reserved_by: userId,
          reservation_expires_at: expiresAt,
        })
        .eq('id', listing.id)
        .eq('status', 'active')
        .select('id');

      if (claim.error) throw new Error(claim.error.message);
      if (affectedRows(claim.data) === 0) {
        throw new Error(
          'This listing could not be reserved — another buyer may have claimed it, or your account is not permitted to reserve it. Nothing has been charged and no order was created.'
        );
      }

      const txn = await supabase.from('domain_marketplace_transactions').insert({
        listing_id: listing.id,
        domain_id: listing.domain_id,
        seller_id: listing.seller_id,
        buyer_id: userId,
        sale_price: listing.buy_now_price,
        currency: listing.currency,
        sale_type: 'buy_now',
        status: 'pending',
        escrow_status: 'pending',
        expires_at: expiresAt,
      });

      if (txn.error) {
        // Release the claim rather than sit on a reservation with no order.
        const release = await supabase
          .from('domain_marketplace_listings')
          .update({
            status: 'active',
            reserved_at: null,
            reserved_by: null,
            reservation_expires_at: null,
          })
          .eq('id', listing.id)
          .eq('reserved_by', userId)
          .select('id');

        if (release.error || affectedRows(release.data) === 0) {
          throw new Error(
            `The order could not be created (${txn.error.message}) and listing ${listing.id} is still marked reserved for you. It will be released automatically when the reservation expires.`
          );
        }
        throw new Error(`The order could not be created: ${txn.error.message}`);
      }

      return { expiresAt };
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/**
 * Attach the buyer's payment reference to a pending order.
 *
 * The reference is typed by the buyer and only marks the order for review — it
 * is never generated here. v2's FounderPool.tsx invented one with
 * `0x${Math.random().toString(16)}`, producing records that looked settled and
 * referenced nothing on any chain.
 */
export function useSubmitPaymentReference() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { transactionId: string; reference: string }) => {
      const reference = input.reference.trim();
      if (reference.length < 8) throw new Error('Enter the full transaction reference.');

      const { data, error } = await supabase
        .from('domain_marketplace_transactions')
        .update({ transaction_hash: reference, escrow_status: 'payment_submitted' })
        .eq('id', input.transactionId)
        .eq('buyer_id', userId!)
        .select('id');

      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) {
        throw new Error('The reference was not saved — this order is no longer open for payment.');
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/**
 * Place a bid.
 *
 * Only the bidder's own row is written. v2 additionally flipped every other
 * bidder's `is_winning_bid` and rewrote the seller's listing — rows a bidder
 * cannot write, so RLS dropped them silently and the displayed high bid drifted
 * away from the bids table. Ranking is the server's job.
 */
export function usePlaceBid() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { listing: DomainListing; amount: number }) => {
      if (!userId) throw new Error('You must be signed in to bid.');
      const floor = Math.max(
        Number(input.listing.current_bid ?? 0),
        Number(input.listing.starting_bid ?? 0)
      );
      if (!(input.amount > floor)) throw new Error(`Your bid must be higher than ${floor}.`);

      const { error } = await supabase.from('domain_marketplace_bids').insert({
        listing_id: input.listing.id,
        bidder_id: userId,
        bid_amount: input.amount,
        currency: input.listing.currency,
        // `status` is NOT NULL. v2's BidDialog omitted it entirely.
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/** Withdraw your own bid. One row, owned by the caller. */
export function useWithdrawBid() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (bidId: string) => {
      const { data, error } = await supabase
        .from('domain_marketplace_bids')
        .update({ status: 'withdrawn' })
        .eq('id', bidId)
        .eq('bidder_id', userId!)
        .eq('status', 'pending')
        .select('id');
      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) throw new Error('This bid can no longer be withdrawn.');
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/* --------------------------------------------------------- STR domains side */

/**
 * Register interest in a name.
 *
 * The row is created `pending` and an operator approves and mints it. Nothing
 * is charged here and the status is not self-assigned — v2 had a second form
 * that inserted `status: 'approved'` with `approved_by` set to the requester.
 */
export function useRequestDomain() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { domainName: string; domainType: string }) => {
      const name = input.domainName.trim().toLowerCase();
      if (!/^[a-z0-9-]{3,32}$/.test(name)) {
        throw new Error('Use 3–32 characters: lowercase letters, numbers or hyphens.');
      }

      // Checked, unlike v2's pre-check, which read a failed request as "free".
      const available = await supabase.rpc('is_domain_available_for_listing', {
        p_domain_name: name,
      });
      if (available.error) throw new Error(available.error.message);
      if (available.data !== true) throw new Error(`${name}.str is already taken.`);

      const { error } = await supabase.from('str_domains').insert({
        user_id: userId!,
        domain_name: name,
        domain_type: input.domainType,
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/**
 * Choose the main domain.
 *
 * Two updates, both on rows the caller owns, ordered so the failure mode is
 * harmless: the old flag is cleared first, so a failure at the second step
 * leaves no main domain rather than two. v2 ran them the other way and never
 * checked the first (DomainMinting.tsx:326-330), so a dropped update produced
 * two main domains and a success toast.
 */
export function useSetMainDomain() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (domainId: string) => {
      const cleared = await supabase
        .from('str_domains')
        .update({ is_main_domain: false, updated_at: new Date().toISOString() })
        .eq('user_id', userId!)
        .eq('is_main_domain', true)
        .neq('id', domainId)
        .select('id');
      if (cleared.error) throw new Error(cleared.error.message);

      const set = await supabase
        .from('str_domains')
        .update({ is_main_domain: true, updated_at: new Date().toISOString() })
        .eq('id', domainId)
        .eq('user_id', userId!)
        .select('id');
      if (set.error) throw new Error(set.error.message);
      if (affectedRows(set.data) === 0) {
        throw new Error(
          affectedRows(cleared.data) > 0
            ? 'The new main domain could not be set, and your previous one was cleared. Pick a main domain again.'
            : 'That domain could not be set as your main domain.'
        );
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/**
 * Register a minted domain with the STR network.
 *
 * Insert or update is decided from the row already in the cache rather than an
 * upsert, because no unique constraint on (user_id, domain_name) is guaranteed
 * and a wrong `onConflict` fails at runtime, not at compile time.
 */
export function useConnectDomain() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { domainName: string; existingId: string | null }) => {
      if (input.existingId) {
        const { data, error } = await supabase
          .from('str_domain_connections')
          .update({ connection_status: 'requested', updated_at: new Date().toISOString() })
          .eq('id', input.existingId)
          .eq('user_id', userId!)
          .select('id');
        if (error) throw new Error(error.message);
        if (affectedRows(data) === 0) throw new Error('The connection could not be updated.');
        return;
      }

      const { error } = await supabase.from('str_domain_connections').insert({
        user_id: userId!,
        domain_name: input.domainName,
        connection_status: 'requested',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/**
 * Provision the wallet for a minted domain.
 *
 * The keypair is generated inside the `create-domain-wallet` edge function; the
 * browser never sees or writes `private_key_encrypted`. `functions.invoke`
 * resolves with `{ data, error }` rather than throwing, so both are inspected —
 * v2's bulk mint discarded the result entirely (DomainMinting.tsx:615-620) and
 * reported "N domains minted with wallets created" even when every call failed.
 */
export function useCreateDomainWallet() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (domainId: string) => {
      const { data, error } = await supabase.functions.invoke<{ success?: boolean; error?: string }>(
        'create-domain-wallet',
        { body: { domain_id: domainId, user_id: userId } }
      );
      if (error) throw new Error(error.message);
      if (data && data.success === false) {
        throw new Error(data.error ?? 'The wallet could not be created.');
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

/* ------------------------------------------------------------ merchant side */

export type BusinessDomain = Pick<
  Tables['business_domains']['Row'],
  'id' | 'domain_name' | 'business_name' | 'business_type' | 'status'
>;

/**
 * What a merchant application needs before it can be submitted.
 *
 * `merchant_account_applications.personal_banking_id` and `business_domain_id`
 * are both NOT NULL, so the form is only offered once both exist. v2 rendered
 * the form regardless and failed at insert time.
 */
export function useMerchantEligibility() {
  const userId = useUserId();
  return useQuery({
    queryKey: ['marketplace', 'merchant-eligibility', userId ?? 'anon'],
    enabled: !!userId,
    queryFn: async () => {
      const [banking, domains] = await Promise.all([
        supabase
          .from('ccoin_bank_applications')
          .select('id')
          .eq('user_id', userId!)
          .eq('status', 'approved')
          .limit(1)
          .maybeSingle(),
        supabase
          .from('business_domains')
          .select('id, domain_name, business_name, business_type, status')
          .eq('user_id', userId!)
          .eq('status', 'active'),
      ]);
      if (banking.error) throw new Error(banking.error.message);
      if (domains.error) throw new Error(domains.error.message);
      return {
        personalBankingId: banking.data?.id ?? null,
        businessDomains: (domains.data ?? []) satisfies BusinessDomain[],
      };
    },
  });
}

export function useApplyForMerchantAccount() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      businessName: string;
      businessDomainId: string;
      personalBankingId: string;
      businessDescription: string | null;
      productsServices: string | null;
      expectedMonthlyVolume: string | null;
      averageTransactionSize: string | null;
      wantsMultiCurrencyIban: boolean;
      wantsPaymentProcessing: boolean;
    }) => {
      if (!input.businessName.trim()) throw new Error('Enter your business name.');
      const { error } = await supabase.from('merchant_account_applications').insert({
        user_id: userId!,
        business_name: input.businessName.trim(),
        business_domain_id: input.businessDomainId,
        personal_banking_id: input.personalBankingId,
        business_description: input.businessDescription,
        products_services: input.productsServices,
        expected_monthly_volume: input.expectedMonthlyVolume,
        average_transaction_size: input.averageTransactionSize,
        requested_products: {
          multi_currency_iban: input.wantsMultiCurrencyIban,
          payment_processing: input.wantsPaymentProcessing,
        },
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

export function useCreateProduct() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      merchantRowId: string;
      productName: string;
      description: string | null;
      category: string | null;
      price: number;
      priceCurrency: string;
      stockQuantity: number | null;
      isDigital: boolean;
    }) => {
      if (!input.productName.trim()) throw new Error('Enter a product name.');
      if (!Number.isFinite(input.price) || input.price < 0) throw new Error('Enter a valid price.');

      // No crypto price is written. v2's POS persisted hardcoded "simulated"
      // exchange rates and the dashboard then summed them as real revenue.
      const { error } = await supabase.from('merchant_products').insert({
        user_id: userId!,
        merchant_id: input.merchantRowId,
        product_name: input.productName.trim(),
        description: input.description,
        category: input.category,
        price: input.price,
        price_currency: input.priceCurrency,
        stock_quantity: input.stockQuantity,
        is_digital: input.isDigital,
        is_active: true,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

export function useSetProductActive() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { productId: string; isActive: boolean }) => {
      // Ownership columns are never rewritten by an edit — v2's update resent
      // merchant_id and user_id on every save.
      const { data, error } = await supabase
        .from('merchant_products')
        .update({ is_active: input.isActive, updated_at: new Date().toISOString() })
        .eq('id', input.productId)
        .eq('user_id', userId!)
        .select('id');
      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) {
        throw new Error('The product was not updated — it may no longer exist.');
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}

export function useDeleteProduct() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (productId: string) => {
      const { data, error } = await supabase
        .from('merchant_products')
        .delete()
        .eq('id', productId)
        .eq('user_id', userId!)
        .select('id');
      if (error) throw new Error(error.message);
      if (affectedRows(data) === 0) {
        throw new Error('The product was not deleted — it may already be gone.');
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: mqk.all }),
  });
}


/* --------------------------------------------------------- str.dome / eSIM */

const STR_DOME_COLS =
  'id, str_dome_username, package_name, package_price_usd, esim_country, esim_file_path, delivery_email, deliver_to_wallet, status, admin_notes, reviewed_at, created_at';

export type StrDomeRequest = {
  id: string;
  str_dome_username: string | null;
  package_name: string | null;
  package_price_usd: number | null;
  esim_country: string | null;
  esim_file_path: string | null;
  delivery_email: string | null;
  deliver_to_wallet: boolean | null;
  status: string | null;
  admin_notes: string | null;
  reviewed_at: string | null;
  created_at: string | null;
};

/** The member's str.dome package requests — the record an eSIM hangs off. */
export function useStrDomeRequests() {
  const userId = useUserId();
  return useQuery({
    queryKey: mqk.strDomeRequests(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      (unwrap(
        await supabase
          .from('str_dome_requests')
          .select(STR_DOME_COLS)
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? []) satisfies StrDomeRequest[],
  });
}

/**
 * Request a str.dome package.
 *
 * Inserts a pending request and nothing else. No balance is touched and no
 * entitlement is granted here — an administrator reviews the request and the
 * eSIM file is attached server-side, which is why esim_file_path is not a
 * field the client can set.
 */
export function useRequestStrDome() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      username: string;
      packageName: string;
      priceUsd: number;
      country: string;
      accountEmail: string;
      deliveryEmail: string;
      deliverToWallet: boolean;
    }) => {
      const username = input.username.trim().toLowerCase();
      if (!/^[a-z0-9-]{3,32}$/.test(username)) {
        throw new Error('Use 3–32 characters: lowercase letters, numbers or hyphens.');
      }
      if (!input.country) throw new Error('Choose the country the eSIM is for.');

      const { error } = await supabase.from('str_dome_requests').insert({
        user_id: userId!,
        // NOT NULL with no default — the generated types caught this, which is
        // the sort of omission v2's `as any` hid until it hit the database.
        account_email: input.accountEmail.trim(),
        str_dome_username: username,
        package_name: input.packageName,
        package_price_usd: input.priceUsd,
        esim_country: input.country,
        delivery_email: input.deliveryEmail.trim() || null,
        deliver_to_wallet: input.deliverToWallet,
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: mqk.strDomeRequests(userId ?? 'anon') });
    },
  });
}
