import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import { STR_REFERENCE_PRICE } from './constants';

/**
 * Data access for the investments domain.
 *
 * Three rules hold everywhere in this file, and they are the three v2 broke:
 *
 * 1. Every read is a react-query query keyed under `investments`, so a write
 *    can invalidate every consumer instead of each screen refetching by hand.
 * 2. Every select names its columns. These tables carry applicant PII —
 *    postal addresses, phone numbers, IBANs, IP addresses — and `select('*')`
 *    ships all of it to the browser to render three fields.
 * 3. No mutation here computes a balance. Crediting is a server-side,
 *    single-statement operation or it does not happen. v2 credited from the
 *    browser at roughly 25 sites by reading a balance, adding to it in JS and
 *    writing back a literal, so two concurrent credits silently lost one.
 */

const NS = 'investments';

/** Query keys in one place, so an invalidation cannot miss a consumer. */
export const ik = {
  all: [NS] as const,
  commitments: (userId: string) => [NS, 'commitments', userId] as const,
  listings: (userId: string) => [NS, 'ipo-listings', userId] as const,
  vouchers: (userId: string) => [NS, 'vouchers', userId] as const,
  airdrop: (userId: string) => [NS, 'airdrop', userId] as const,
  affiliate: (userId: string) => [NS, 'affiliate', userId] as const,
  referrals: (affiliateId: string) => [NS, 'referrals', affiliateId] as const,
  founder: (userId: string) => [NS, 'founder', userId] as const,
  starw: (userId: string) => [NS, 'starw', userId] as const,
  holdings: (userId: string) => [NS, 'holdings', userId] as const,
  admin: (queue: string, status: string) => [NS, 'admin', queue, status] as const,
  adminAll: [NS, 'admin'] as const,
};

/** Throw on a Supabase error so react-query can surface it in an ErrorState. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/* ========================================================== commitments == */

/** The kinds of commitment a member can hold, across six tables. */
export type CommitmentKind =
  | 'seed_str'
  | 'private_seed_str'
  | 'str_ipo'
  | 'str_prelisting'
  | 'digital_shares'
  | 'safe';

export interface Commitment {
  id: string;
  kind: CommitmentKind;
  offering: string;
  /** Review status of the application, where the table has one. */
  status: string;
  /** Settlement status, where the table tracks it separately. */
  paymentStatus: string | null;
  amountUsd: number;
  quantity: number | null;
  quantityUnit: string | null;
  createdAt: string;
  /** Deadline by which payment must reach the treasury, if one applies. */
  paymentDeadline: string | null;
}

/**
 * Everything the member has subscribed to, normalised into one list.
 *
 * v2 spread this across six pages that each queried one table, so nobody
 * could see their own position in a single view.
 */
export function useMyCommitments() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.commitments(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<Commitment[]> => {
      const uid = userId!;

      const [seed, privateSeed, ipo, prelisting, shares, safe] = await Promise.all([
        supabase
          .from('seed_str_applications')
          .select(
            'id, status, payment_status, investment_amount, investment_tier, expected_return_rate, created_at, payment_deadline'
          )
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
        supabase
          .from('private_seed_str_applications')
          .select(
            'id, status, payment_status, investment_amount, investment_tier, expected_return_rate, created_at, payment_deadline'
          )
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
        supabase
          .from('private_str_ipo_purchases')
          .select('id, payment_status, usd_amount, str_amount, phase, created_at, payment_deadline')
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
        supabase
          .from('private_str_prelisting_purchases')
          .select('id, payment_status, usd_amount, str_amount, phase, created_at, payment_deadline')
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
        supabase
          .from('private_digital_shares_purchases')
          .select(
            'id, payment_status, wnft_status, total_usd, shares_quantity, created_at, payment_deadline'
          )
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
        supabase
          .from('safe_purchases')
          .select('id, status, total_usd, total_shares, bonus_shares, created_at')
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
      ]);

      const rows: Commitment[] = [];

      // `investment_amount` on both seed tables holds STR units, not USD, and
      // `expected_return_rate` holds a share count. Both are v2 column misuses
      // that the data now depends on; renaming is a migration, so the reading
      // is corrected here rather than the label being left misleading.
      for (const r of unwrap(seed) ?? []) {
        const str = Number(r.investment_amount ?? 0);
        rows.push({
          id: r.id,
          kind: 'seed_str',
          offering: `STR seed round (${r.investment_tier})`,
          status: r.status,
          paymentStatus: r.payment_status,
          amountUsd: str * STR_REFERENCE_PRICE,
          quantity: Number(r.expected_return_rate ?? 0),
          quantityUnit: 'shares',
          createdAt: r.created_at,
          paymentDeadline: r.payment_deadline,
        });
      }

      for (const r of unwrap(privateSeed) ?? []) {
        const str = Number(r.investment_amount ?? 0);
        rows.push({
          id: r.id,
          kind: 'private_seed_str',
          offering: `Private STR seed round${r.investment_tier ? ` (${r.investment_tier})` : ''}`,
          status: r.status ?? 'pending',
          paymentStatus: r.payment_status,
          amountUsd: str * STR_REFERENCE_PRICE,
          quantity: Number(r.expected_return_rate ?? 0),
          quantityUnit: 'shares',
          createdAt: r.created_at ?? new Date(0).toISOString(),
          paymentDeadline: r.payment_deadline,
        });
      }

      for (const r of unwrap(ipo) ?? []) {
        rows.push({
          id: r.id,
          kind: 'str_ipo',
          offering: `STR IPO sale (${r.phase})`,
          status: r.payment_status,
          paymentStatus: r.payment_status,
          amountUsd: Number(r.usd_amount ?? 0),
          quantity: Number(r.str_amount ?? 0),
          quantityUnit: 'STR',
          createdAt: r.created_at,
          paymentDeadline: r.payment_deadline,
        });
      }

      for (const r of unwrap(prelisting) ?? []) {
        rows.push({
          id: r.id,
          kind: 'str_prelisting',
          offering: 'STR pre-listing voucher',
          status: r.payment_status,
          paymentStatus: r.payment_status,
          amountUsd: Number(r.usd_amount ?? 0),
          quantity: Number(r.str_amount ?? 0),
          quantityUnit: 'STR',
          createdAt: r.created_at,
          paymentDeadline: r.payment_deadline,
        });
      }

      for (const r of unwrap(shares) ?? []) {
        rows.push({
          id: r.id,
          kind: 'digital_shares',
          offering: `Digital shares (wNFT ${r.wnft_status})`,
          status: r.payment_status,
          paymentStatus: r.payment_status,
          amountUsd: Number(r.total_usd ?? 0),
          quantity: Number(r.shares_quantity ?? 0),
          quantityUnit: 'shares',
          createdAt: r.created_at,
          paymentDeadline: r.payment_deadline,
        });
      }

      for (const r of unwrap(safe) ?? []) {
        const bonus = Number(r.bonus_shares ?? 0);
        rows.push({
          id: r.id,
          kind: 'safe',
          offering: bonus > 0 ? `SSI SAFE (+${bonus.toLocaleString('en-IE')} bonus)` : 'SSI SAFE',
          status: r.status,
          paymentStatus: null,
          amountUsd: Number(r.total_usd ?? 0),
          quantity: Number(r.total_shares ?? 0),
          quantityUnit: 'shares',
          createdAt: r.created_at,
          paymentDeadline: null,
        });
      }

      return rows.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    },
  });
}

/* ======================================================== IPO listings == */

export function useMyIpoListingRequests() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.listings(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('ipo_listing_requests')
          .select(
            'id, share_type, number_of_shares, price_per_share, total_usd_value, receiving_currency, bank_name, iban, status, admin_message, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

export interface NewIpoListingRequest {
  fullName: string;
  email: string;
  phone: string | null;
  address: string | null;
  shareType: string;
  numberOfShares: number;
  pricePerShare: number;
  receivingCurrency: string;
  iban: string;
  bankName: string;
  bankSwift: string;
}

/**
 * Register an intent to sell holdings into the IPO.
 *
 * This creates a request, not a trade: it moves no balance and settles
 * nothing. `price_per_share` is still sent because the column is NOT NULL,
 * but the row is worthless until an admin approves it, and approval is where
 * the server re-prices from its own book rather than trusting this number.
 */
export function useCreateIpoListingRequest() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewIpoListingRequest) => {
      const { error } = await supabase.from('ipo_listing_requests').insert({
        user_id: userId!,
        full_name: input.fullName,
        email: input.email,
        phone: input.phone,
        address: input.address,
        share_type: input.shareType,
        number_of_shares: input.numberOfShares,
        price_per_share: input.pricePerShare,
        total_usd_value: input.numberOfShares * input.pricePerShare,
        receiving_currency: input.receivingCurrency,
        iban: input.iban,
        bank_name: input.bankName,
        bank_swift: input.bankSwift,
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.listings(userId ?? 'anon') }),
  });
}

/* ============================================================ vouchers == */

export function useMyVouchers() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.vouchers(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const [redemptions, corrections] = await Promise.all([
        supabase
          .from('voucher_redemptions')
          .select(
            'id, token_type, package_type, payment_type, status, credited_amount, tokens_credited, credited_at, admin_notes, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false }),
        supabase
          .from('voucher_corrections')
          .select(
            'id, voucher_id, token_type, package_type, previous_amount, corrected_amount, difference, correction_type, correction_reason, corrected_at'
          )
          .eq('user_id', userId!)
          .order('corrected_at', { ascending: false }),
      ]);

      return {
        redemptions: unwrap(redemptions) ?? [],
        corrections: unwrap(corrections) ?? [],
      };
    },
  });
}

export interface NewVoucherRedemption {
  tokenType: string;
  packageType: string;
  paymentType: string;
  fullName: string;
  emailAddress: string;
  strDomeUsername: string;
  strDomeEmail: string;
  depositAddress: string | null;
  paymentHash: string | null;
  confirmationNumber: string | null;
  amount: string | null;
}

/**
 * Claim a voucher.
 *
 * The row is created as `pending` with no credited amount. Whether the voucher
 * is real, and how many tokens it is worth, is decided server-side on review —
 * this mutation deliberately cannot set `credited_amount` or `tokens_credited`,
 * because a client that could set them could mint tokens.
 */
export function useRedeemVoucher() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewVoucherRedemption) => {
      const { error } = await supabase.from('voucher_redemptions').insert({
        user_id: userId!,
        token_type: input.tokenType,
        package_type: input.packageType,
        payment_type: input.paymentType,
        full_name: input.fullName,
        email_address: input.emailAddress,
        str_dome_username: input.strDomeUsername,
        str_dome_email: input.strDomeEmail,
        deposit_address: input.depositAddress,
        payment_hash: input.paymentHash,
        confirmation_number: input.confirmationNumber,
        amount: input.amount,
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.vouchers(userId ?? 'anon') }),
  });
}

/* ============================================================= airdrop == */

export function useMyAirdrop() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.airdrop(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('airdrop_registrations')
          .select(
            'id, full_name, email_address, wallet_address, requested_amount, event_type, voucher_type, status, tokens_credited, credited_amount, credited_at, admin_notes, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

export interface NewAirdropRegistration {
  fullName: string;
  emailAddress: string;
  walletAddress: string;
  requestedAmount: number;
  eventType: string;
  voucherType: string | null;
  voucherId: string | null;
}

/** Register for the airdrop. Creates a pending request; credits nothing. */
export function useRegisterAirdrop() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewAirdropRegistration) => {
      const { error } = await supabase.from('airdrop_registrations').insert({
        user_id: userId!,
        full_name: input.fullName,
        email_address: input.emailAddress,
        wallet_address: input.walletAddress,
        requested_amount: input.requestedAmount,
        event_type: input.eventType,
        voucher_type: input.voucherType,
        voucher_id: input.voucherId,
        status: 'pending',
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.airdrop(userId ?? 'anon') }),
  });
}

/* =========================================================== affiliates == */

export function useMyAffiliate() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.affiliate(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('seed_str_affiliates')
          .select(
            'id, affiliate_code, str_domain, status, total_referrals, total_conversions, total_investment_referred, usdt_address, usdt_network, usdc_address, usdc_network, created_at'
          )
          .eq('user_id', userId!)
          .maybeSingle()
      ),
  });
}

export function useAffiliateReferrals(affiliateId: string | undefined) {
  return useQuery({
    queryKey: ik.referrals(affiliateId ?? 'none'),
    enabled: !!affiliateId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('seed_str_referrals')
          .select('id, status, investment_amount, commission_amount, converted_at, created_at')
          .eq('affiliate_id', affiliateId!)
          .order('created_at', { ascending: false })
          .limit(200)
      ) ?? [],
  });
}

export interface NewAffiliate {
  fullName: string;
  email: string;
  strDomain: string;
  usdtAddress: string | null;
  usdtNetwork: string | null;
  usdcAddress: string | null;
  usdcNetwork: string | null;
}

/**
 * Enrol as a referral affiliate.
 *
 * The affiliate code is derived from the member's own STR domain rather than
 * being chosen, so it cannot collide with, or impersonate, another member's.
 */
export function useCreateAffiliate() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewAffiliate) => {
      const code = input.strDomain.replace(/^str\./i, '').toLowerCase();
      const { error } = await supabase.from('seed_str_affiliates').insert({
        user_id: userId!,
        affiliate_code: code,
        str_domain: code,
        full_name: input.fullName,
        email: input.email,
        usdt_address: input.usdtAddress,
        usdt_network: input.usdtNetwork,
        usdc_address: input.usdcAddress,
        usdc_network: input.usdcNetwork,
      });
      if (error) {
        // 23505 is the unique violation on affiliate_code.
        throw new Error(
          error.code === '23505'
            ? 'That STR domain is already registered as an affiliate.'
            : error.message
        );
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.affiliate(userId ?? 'anon') }),
  });
}

/* =============================================================== founder == */

/**
 * Founder pools, positions and their ledger.
 *
 * Access is decided by the `founder_access` row, which is written server-side
 * and enforced by RLS — this hook simply reports whether one exists so the UI
 * can say why a section is empty. v2 gated the same screens on a shared access
 * code held in the client; a code in a bundle is not a permission.
 */
export function useFounderPortfolio() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.founder(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const uid = userId!;

      const [access, pools, positions, transactions] = await Promise.all([
        supabase
          .from('founder_access')
          .select('id, is_active, access_granted_at, last_access')
          .eq('user_id', uid)
          .maybeSingle(),
        supabase
          .from('founder_pools')
          .select('id, pool_type, balance, usd_value, last_price, is_founder_position, updated_at')
          .eq('user_id', uid),
        supabase
          .from('founder_positions')
          .select(
            'id, position_number, title, status, is_prime, current_usd_value, max_usd_limit, min_deposit_usd, deposit_date, lock_end_date, withdrawal_available_date, withdrawal_executed, input_btc_amount, output_btc_amount, ccos_mint_percentage, unique_link_id'
          )
          .eq('user_id', uid)
          .order('position_number'),
        supabase
          .from('founder_pool_transactions')
          .select(
            'id, pool_type, transaction_type, amount, usd_value_at_time, ccos_minted, mint_percentage, transaction_hash, status, created_at'
          )
          .eq('user_id', uid)
          .order('created_at', { ascending: false })
          .limit(50),
      ]);

      if (access.error) throw new Error(access.error.message);

      return {
        hasAccess: !!access.data?.is_active,
        pools: unwrap(pools) ?? [],
        positions: unwrap(positions) ?? [],
        transactions: unwrap(transactions) ?? [],
      };
    },
  });
}

/* ================================================================ StarW == */

export function useStarwHoldings() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.starw(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const uid = userId!;

      const [nodes, supers, purchases, rewards] = await Promise.all([
        supabase
          .from('starw_nodes')
          .select('id, node_number, status, worker_nodes_count, assigned_at')
          .eq('user_id', uid)
          .order('node_number'),
        supabase
          .from('supernodes')
          .select('id, node_number, status, worker_nodes_count, assigned_at')
          .eq('user_id', uid)
          .order('node_number'),
        supabase
          .from('starw_purchases')
          .select('id, node_count, total_cost, status, stage, arss_bonus, created_at, processed_at')
          .eq('user_id', uid)
          .order('created_at', { ascending: false }),
        supabase
          .from('starw_wstr_rewards')
          .select('id, starw_node_id, reward_amount, reward_date, status')
          .eq('user_id', uid)
          .order('reward_date', { ascending: false })
          .limit(60),
      ]);

      return {
        nodes: unwrap(nodes) ?? [],
        supernodes: unwrap(supers) ?? [],
        purchases: unwrap(purchases) ?? [],
        rewards: unwrap(rewards) ?? [],
      };
    },
  });
}

/* ============================================================= holdings == */

/** Share balances and anything still vesting. */
export function useShareHoldings() {
  const userId = useUserId();

  return useQuery({
    queryKey: ik.holdings(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () => {
      const uid = userId!;

      const [shares, vesting] = await Promise.all([
        supabase
          .from('user_str_shares')
          .select('id, balance, locked_balance, wnft_shares, vesting_end_date, updated_at')
          .eq('user_id', uid)
          .maybeSingle(),
        supabase
          .from('vesting_tokens')
          .select(
            'id, token_type, amount, source, status, vesting_months, vesting_start_date, vesting_end_date, released_at'
          )
          .eq('user_id', uid)
          .order('vesting_end_date'),
      ]);

      if (shares.error) throw new Error(shares.error.message);

      return { shares: shares.data, vesting: unwrap(vesting) ?? [] };
    },
  });
}

/* ================================================================ admin == */

/**
 * Whether the signed-in user holds seed-round review rights.
 *
 * Answered by the database, not by a role string the client picked up. The
 * route is already guarded on `admin`; this narrows the seed queues further
 * without the UI having to reimplement the rule.
 */
export function useSeedStrAdminAccess() {
  const userId = useUserId();

  return useQuery({
    queryKey: [NS, 'seed-admin', userId ?? 'anon'],
    enabled: !!userId,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('has_seed_str_admin_access', {
        check_user_id: userId!,
      });
      if (error) throw new Error(error.message);
      return data === true;
    },
  });
}

export function useAdminSeedApplications(status: string) {
  return useQuery({
    queryKey: ik.admin('seed', status),
    queryFn: async () => {
      let q = supabase
        .from('seed_str_applications')
        .select(
          'id, user_id, full_name, email, investment_tier, investment_amount, expected_return_rate, status, payment_status, payment_hash, credited_amount, str_shares_credited, application_date, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

export function useAdminPrivateApplications(status: string) {
  return useQuery({
    queryKey: ik.admin('private-seed', status),
    queryFn: async () => {
      let q = supabase
        .from('private_seed_str_applications')
        .select(
          'id, user_id, full_name, email, investment_tier, investment_amount, expected_return_rate, status, payment_status, payment_hash, credited_amount, str_shares_credited, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

export function useAdminVouchers(status: string) {
  return useQuery({
    queryKey: ik.admin('vouchers', status),
    queryFn: async () => {
      let q = supabase
        .from('voucher_redemptions')
        .select(
          'id, user_id, full_name, email_address, token_type, package_type, payment_type, status, credited_amount, tokens_credited, credited_at, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

export function useAdminAirdrop(status: string) {
  return useQuery({
    queryKey: ik.admin('airdrop', status),
    queryFn: async () => {
      let q = supabase
        .from('airdrop_registrations')
        .select(
          'id, user_id, full_name, email_address, wallet_address, requested_amount, event_type, voucher_type, status, tokens_credited, credited_amount, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

/** Every assigned StarW node, joined to its holder by the database. */
export function useAdminStarwNodes() {
  return useQuery({
    queryKey: ik.admin('starw-nodes', 'all'),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_get_starw_nodes');
      if (error) throw new Error(error.message);
      return data ?? [];
    },
  });
}

/**
 * Move a voucher to a new status.
 *
 * Goes through `process_voucher_redemption_with_audit`, which performs the
 * status change, the crediting and the audit entry in one database call. That
 * is the whole point: v2's admin screens read a balance, added the voucher
 * amount in JavaScript and wrote the sum back, so approving two vouchers at
 * once credited one of them.
 *
 * The route is guarded on `admin`, but the guard is only a UI convenience —
 * the function is expected to verify `auth.uid()` itself and to treat
 * `performed_by_user_id` as attribution, not as authorisation.
 */
export function useReviewVoucher() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { voucherId: string; status: string; notes?: string }) => {
      const { error } = await supabase.rpc('process_voucher_redemption_with_audit', {
        voucher_id: input.voucherId,
        new_status: input.status,
        performed_by_user_id: userId!,
        admin_notes_param: input.notes,
        user_agent_param: navigator.userAgent,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.adminAll }),
  });
}

/** Recompute a voucher's token amount from the package table, server-side. */
export function useCorrectVoucherTokens() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (voucherId: string) => {
      const { error } = await supabase.rpc('admin_correct_voucher_tokens', {
        voucher_id_param: voucherId,
        admin_user_id: userId!,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.adminAll }),
  });
}

/** Set a voucher to an explicit amount, with a reason recorded. */
export function useCorrectVoucherAmount() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: { voucherId: string; amount: number; reason: string }) => {
      const { error } = await supabase.rpc('correct_voucher_amount', {
        p_voucher_id: input.voucherId,
        p_corrected_amount: input.amount,
        p_correction_reason: input.reason,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.adminAll }),
  });
}

/** Assign a block of StarW nodes to a member. */
export function useAssignStarwNodes() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      targetUserId: string;
      nodeCount: number;
      startNumber: number;
      workerNodes: number;
      status: string;
    }) => {
      const { error } = await supabase.rpc('admin_assign_starw_nodes', {
        target_user_id: input.targetUserId,
        node_count: input.nodeCount,
        start_number: input.startNumber,
        worker_nodes: input.workerNodes,
        node_status: input.status,
        admin_user_id: userId ?? undefined,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.adminAll }),
  });
}

export interface VoucherSweepResult {
  success?: boolean;
  dryRun?: boolean;
  total_scanned?: number;
  total_corrections?: number;
}

/**
 * Bulk voucher repair jobs.
 *
 * Both run under the service role inside the edge function, which re-checks
 * the caller's role before touching anything. `dryRun` is honoured by
 * `correct-precex-vouchers`, so a sweep can be inspected before it is applied.
 */
export function useVoucherSweep() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: {
      job: 'correct-precex-vouchers' | 'correct-str-vouchers-targeted';
      dryRun: boolean;
    }) => {
      const { data, error } = await supabase.functions.invoke<VoucherSweepResult>(input.job, {
        body: input.job === 'correct-precex-vouchers' ? { dryRun: input.dryRun } : {},
      });
      if (error) throw new Error(error.message);
      return data ?? {};
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ik.adminAll }),
  });
}
