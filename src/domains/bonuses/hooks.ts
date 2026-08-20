import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';
import { assertCreditingAllowed } from './safeMode';
import { REWARD_SOURCES, type RewardSource } from './constants';

/**
 * Every read and write the bonuses domain performs.
 *
 * Four rules hold throughout, each one a v2 defect turned into a constraint:
 *
 * 1. Nothing here credits or debits a balance from the browser. A crediting
 *    action is an RPC or an edge function, or it is rendered disabled with the
 *    reason on screen. v2 credited from the client at roughly 25 sites by
 *    reading a balance, adding to it in JavaScript and writing the sum back, so
 *    two concurrent approvals silently lost one.
 * 2. A running total is never derived from a balance column. v2's airdrop
 *    approval wrote `total_earned = arss_balance + amount`, so the second
 *    credit to an account overwrote the lifetime figure with the current
 *    balance instead of accumulating. `total_earned` is read here and never
 *    computed.
 * 3. A counter is either counted by the server or not shown. v2 incremented
 *    `seed_str_affiliates.total_referrals` from an anonymous page visit, so any
 *    visitor could inflate it by refreshing a referral link. The referral
 *    figures below come from `count: 'exact'` over the referral rows.
 * 4. Every write destructures `{ error }` and throws on it, and every select
 *    names its columns. These tables carry names, email addresses, wallet
 *    addresses and IP addresses that no screen in this domain renders.
 */

const NS = 'bonuses';

type Tables = Database['public']['Tables'];

/** Query keys in one place, so an invalidation cannot miss a consumer. */
export const bk = {
  all: [NS] as const,
  summary: (userId: string) => [NS, 'summary', userId] as const,
  profile: (userId: string) => [NS, 'profile', userId] as const,
  vouchers: (userId: string) => [NS, 'vouchers', userId] as const,
  airdrop: (userId: string) => [NS, 'airdrop', userId] as const,
  referrals: (userId: string) => [NS, 'referrals', userId] as const,
  affiliate: (userId: string) => [NS, 'affiliate', userId] as const,
  affiliateReferrals: (affiliateId: string) => [NS, 'affiliate-referrals', affiliateId] as const,
  admin: (queue: string, status: string) => [NS, 'admin', queue, status] as const,
  adminVoucherHistory: (voucherId: string) => [NS, 'admin', 'voucher-history', voucherId] as const,
  adminAll: [NS, 'admin'] as const,
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

/**
 * Normalise a token symbol for grouping.
 *
 * `str_stable` is the same asset as `str` on these tables and v2 treated the
 * two as different currencies on every screen that summed them.
 */
export function normaliseToken(raw: string | null | undefined): string {
  const t = (raw ?? '').trim().toLowerCase();
  if (t === 'str_stable') return 'str';
  return t || 'unknown';
}

/* ==================================================== the reward ledger == */

/**
 * One reward, from whichever table it came out of.
 *
 * `amount` is `null` when the server has not yet decided what the reward is
 * worth. That is deliberately different from `0`: a pending voucher has no
 * agreed value, and the browser must not invent one by looking the package up
 * in its own price table and presenting the result as money owed.
 */
export interface RewardEvent {
  id: string;
  source: RewardSource;
  /** Token symbol, or 'usd' for a cash commission. */
  token: string;
  amount: number | null;
  status: 'credited' | 'pending' | 'declined';
  /** When it was credited, or when it was raised if it has not been. */
  at: string;
  /** Free text for the row, e.g. the verbatim package label. */
  detail: string;
}

export interface TokenTotals {
  token: string;
  earned: number;
  pending: number;
  /** Pending rows the server has put no figure against yet. */
  unvalued: number;
}

export interface ArssWalletSnapshot {
  balance: number;
  /**
   * Lifetime earned, as recorded by the server.
   *
   * Read only. v2 wrote this column from `arss_balance + amount`, which is not
   * a lifetime total — it is the balance, restated. Nothing in v3 computes it.
   */
  totalEarned: number;
  totalSpent: number;
  updatedAt: string;
}

export interface RewardsSummary {
  events: RewardEvent[];
  totals: TokenTotals[];
  arssWallet: ArssWalletSnapshot | null;
}

const CREDITED_STARW_STATUSES = new Set(['paid', 'credited', 'completed', 'approved']);

/**
 * Everything the member has earned, across the five tables that pay out.
 *
 * v2 had a page per source and no view that put them together, so a member
 * could not answer "what have I been given" without visiting five screens and
 * adding up by hand.
 */
export function useRewardsSummary() {
  const userId = useUserId();

  return useQuery({
    queryKey: bk.summary(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<RewardsSummary> => {
      const uid = userId!;

      const [vouchers, airdrops, referrals, starw, wallet, affiliate] = await Promise.all([
        supabase
          .from('voucher_redemptions')
          .select('id, token_type, package_type, status, credited_amount, tokens_credited, credited_at, created_at')
          .eq('user_id', uid)
          .order('created_at', { ascending: false })
          .limit(500),
        supabase
          .from('airdrop_registrations')
          .select('id, event_type, requested_amount, status, credited_amount, tokens_credited, credited_at, created_at')
          .eq('user_id', uid)
          .order('created_at', { ascending: false })
          .limit(500),
        supabase
          .from('referrals')
          .select('id, status, reward_amount, reward_claimed, claimed_at, created_at')
          .eq('referrer_id', uid)
          .order('created_at', { ascending: false })
          .limit(500),
        supabase
          .from('starw_wstr_rewards')
          .select('id, reward_amount, reward_date, status')
          .eq('user_id', uid)
          .order('reward_date', { ascending: false })
          .limit(500),
        supabase
          .from('user_wallets')
          .select('arss_balance, total_earned, total_spent, updated_at')
          .eq('user_id', uid)
          .maybeSingle(),
        supabase.from('seed_str_affiliates').select('id').eq('user_id', uid).maybeSingle(),
      ]);

      if (wallet.error) throw new Error(wallet.error.message);
      if (affiliate.error) throw new Error(affiliate.error.message);

      const events: RewardEvent[] = [];

      for (const v of unwrap(vouchers) ?? []) {
        const credited = v.tokens_credited === true;
        const declined = v.status === 'rejected' || v.status === 'cancelled';
        events.push({
          id: `voucher:${v.id}`,
          source: 'voucher',
          token: normaliseToken(v.token_type),
          // Only the server's own figure. A pending voucher has no value yet.
          amount: v.credited_amount === null ? null : Number(v.credited_amount),
          status: credited ? 'credited' : declined ? 'declined' : 'pending',
          at: v.credited_at ?? v.created_at,
          // Verbatim. The label is matched byte for byte by the correction jobs.
          detail: v.package_type,
        });
      }

      for (const a of unwrap(airdrops) ?? []) {
        const credited = a.tokens_credited === true;
        const declined = a.status === 'rejected';
        events.push({
          id: `airdrop:${a.id}`,
          source: 'airdrop',
          token: 'arss',
          amount: a.credited_amount === null ? null : Number(a.credited_amount),
          status: credited ? 'credited' : declined ? 'declined' : 'pending',
          at: a.credited_at ?? a.created_at,
          detail: credited
            ? `${a.event_type ?? 'Airdrop'} allocation`
            : `${a.event_type ?? 'Airdrop'} — requested ${a.requested_amount}`,
        });
      }

      for (const r of unwrap(referrals) ?? []) {
        const claimed = r.reward_claimed === true;
        events.push({
          id: `referral:${r.id}`,
          source: 'referral',
          token: 'wstr',
          amount: r.reward_amount === null ? null : Number(r.reward_amount),
          status: claimed ? 'credited' : r.status === 'cancelled' ? 'declined' : 'pending',
          at: r.claimed_at ?? r.created_at,
          detail: claimed ? 'Referral commission released' : 'Referral commission awaiting release',
        });
      }

      for (const s of unwrap(starw) ?? []) {
        events.push({
          id: `starw:${s.id}`,
          source: 'starw',
          token: 'wstr',
          amount: Number(s.reward_amount),
          status: CREDITED_STARW_STATUSES.has(s.status) ? 'credited' : 'pending',
          at: s.reward_date,
          detail: 'StarW node reward',
        });
      }

      // Affiliate commissions hang off the affiliate row, so they need its id.
      if (affiliate.data?.id) {
        const commissions = await supabase
          .from('seed_str_referrals')
          .select('id, status, commission_amount, converted_at, created_at')
          .eq('affiliate_id', affiliate.data.id)
          .not('commission_amount', 'is', null)
          .order('created_at', { ascending: false })
          .limit(500);

        for (const c of unwrap(commissions) ?? []) {
          events.push({
            id: `affiliate:${c.id}`,
            source: 'affiliate',
            token: 'usd',
            amount: c.commission_amount === null ? null : Number(c.commission_amount),
            status: c.converted_at ? 'credited' : 'pending',
            at: c.converted_at ?? c.created_at,
            detail: 'Seed round affiliate commission',
          });
        }
      }

      events.sort((a, b) => b.at.localeCompare(a.at));

      const byToken = new Map<string, TokenTotals>();
      for (const e of events) {
        if (e.status === 'declined') continue;
        const row = byToken.get(e.token) ?? { token: e.token, earned: 0, pending: 0, unvalued: 0 };
        if (e.status === 'credited') row.earned += e.amount ?? 0;
        else if (e.amount === null) row.unvalued += 1;
        else row.pending += e.amount;
        byToken.set(e.token, row);
      }

      const w = wallet.data;

      return {
        events,
        totals: [...byToken.values()].sort((a, b) => a.token.localeCompare(b.token)),
        arssWallet: w
          ? {
              balance: Number(w.arss_balance),
              totalEarned: Number(w.total_earned),
              totalSpent: Number(w.total_spent),
              updatedAt: w.updated_at,
            }
          : null,
      };
    },
  });
}

/* ----------------------------------------------------- chart derivations */

export interface MonthPoint {
  label: string;
  value: number;
}

/**
 * Credited rewards per month for one token, cumulative.
 *
 * Only credited events count. Showing pending amounts on the same line would
 * draw a total the member has not been given.
 */
export function cumulativeByMonth(events: RewardEvent[], token: string): MonthPoint[] {
  const buckets = new Map<string, number>();

  for (const e of events) {
    if (e.status !== 'credited' || e.token !== token || e.amount === null) continue;
    const key = e.at.slice(0, 7); // YYYY-MM, sorts lexicographically
    buckets.set(key, (buckets.get(key) ?? 0) + e.amount);
  }

  let running = 0;
  return [...buckets.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => {
      running += value;
      const [y, m] = key.split('-');
      const label = new Date(Number(y), Number(m) - 1, 1).toLocaleDateString('en-IE', {
        month: 'short',
        year: '2-digit',
      });
      return { label, value: running };
    });
}

export interface SourcePoint {
  label: string;
  value: number;
  /** Index into the chart palette, fixed per source so colours never shuffle. */
  index: number;
}

/** Credited total per source for one token, in the fixed source order. */
export function creditedBySource(
  events: RewardEvent[],
  token: string,
  labels: Record<RewardSource, string>
): SourcePoint[] {
  const totals = new Map<RewardSource, number>();

  for (const e of events) {
    if (e.status !== 'credited' || e.token !== token || e.amount === null) continue;
    totals.set(e.source, (totals.get(e.source) ?? 0) + e.amount);
  }

  return REWARD_SOURCES.map((source, index) => ({
    label: labels[source],
    value: totals.get(source) ?? 0,
    index,
  })).filter((p) => p.value > 0);
}

/* ============================================================= profile == */

export interface BonusProfile {
  fullName: string;
  emailAddress: string;
  strWalletAddress: string | null;
  strDomainOwned: string;
  strDomainUsername: string;
  referralCode: string | null;
  /** The member's main str.domain, if one has been minted. */
  mainDomain: string | null;
}

/**
 * The member's own identity fields, used to prefill the forms.
 *
 * v2 asked the member to retype their name, email, domain and wallet address
 * into every one of these forms, then stored whatever they typed — which is why
 * the voucher tables hold several spellings of the same person.
 */
export function useBonusProfile() {
  const userId = useUserId();

  return useQuery({
    queryKey: bk.profile(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<BonusProfile | null> => {
      const uid = userId!;

      const [profile, domain] = await Promise.all([
        supabase
          .from('user_profiles')
          .select('full_name, email_address, str_wallet_address, str_domain_owned, str_domain_username, referral_code')
          .eq('user_id', uid)
          .maybeSingle(),
        supabase
          .from('str_domains')
          .select('domain_name')
          .eq('user_id', uid)
          .eq('is_main_domain', true)
          .maybeSingle(),
      ]);

      if (profile.error) throw new Error(profile.error.message);
      if (domain.error) throw new Error(domain.error.message);
      if (!profile.data) return null;

      return {
        fullName: profile.data.full_name,
        emailAddress: profile.data.email_address,
        strWalletAddress: profile.data.str_wallet_address,
        strDomainOwned: profile.data.str_domain_owned,
        strDomainUsername: profile.data.str_domain_username,
        referralCode: profile.data.referral_code,
        mainDomain: domain.data?.domain_name ?? null,
      };
    },
  });
}

/* ============================================================ vouchers == */

export type VoucherRow = Pick<
  Tables['voucher_redemptions']['Row'],
  | 'id'
  | 'token_type'
  | 'package_type'
  | 'payment_type'
  | 'status'
  | 'credited_amount'
  | 'tokens_credited'
  | 'credited_at'
  | 'admin_notes'
  | 'created_at'
>;

export type CorrectionRow = Pick<
  Tables['voucher_corrections']['Row'],
  | 'id'
  | 'voucher_id'
  | 'token_type'
  | 'package_type'
  | 'previous_amount'
  | 'corrected_amount'
  | 'difference'
  | 'correction_type'
  | 'correction_reason'
  | 'corrected_at'
>;

/** The member's own voucher claims and any restatements applied to them. */
export function useMyVouchers() {
  const userId = useUserId();

  return useQuery({
    queryKey: bk.vouchers(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<{ redemptions: VoucherRow[]; corrections: CorrectionRow[] }> => {
      const uid = userId!;

      const [redemptions, corrections] = await Promise.all([
        supabase
          .from('voucher_redemptions')
          .select(
            'id, token_type, package_type, payment_type, status, credited_amount, tokens_credited, credited_at, admin_notes, created_at'
          )
          .eq('user_id', uid)
          .order('created_at', { ascending: false })
          .limit(200),
        supabase
          .from('voucher_corrections')
          .select(
            'id, voucher_id, token_type, package_type, previous_amount, corrected_amount, difference, correction_type, correction_reason, corrected_at'
          )
          .eq('user_id', uid)
          .order('corrected_at', { ascending: false })
          .limit(200),
      ]);

      return {
        redemptions: unwrap(redemptions) ?? [],
        corrections: unwrap(corrections) ?? [],
      };
    },
  });
}

export interface NewVoucherClaim {
  tokenType: string;
  /** Must be a `value` from constants.ts, written through unchanged. */
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
 * Submit a voucher claim.
 *
 * The row is created as `pending` with no credited amount. This mutation
 * deliberately cannot set `credited_amount`, `tokens_credited` or `status` to
 * anything else: a client that could set them could mint tokens. What the
 * voucher is worth is decided server-side on review, against the server's own
 * package table.
 *
 * `packageType` is inserted exactly as given. No trimming, no case change, no
 * number formatting — see the note at the top of constants.ts.
 */
export function useSubmitVoucherClaim() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewVoucherClaim) => {
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
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: bk.vouchers(userId ?? 'anon') });
      void qc.invalidateQueries({ queryKey: bk.summary(userId ?? 'anon') });
    },
  });
}

/* ============================================================= airdrop == */

export type AirdropRow = Pick<
  Tables['airdrop_registrations']['Row'],
  | 'id'
  | 'event_type'
  | 'voucher_type'
  | 'requested_amount'
  | 'status'
  | 'credited_amount'
  | 'tokens_credited'
  | 'credited_at'
  | 'admin_notes'
  | 'created_at'
>;

export function useMyAirdrop() {
  const userId = useUserId();

  return useQuery({
    queryKey: bk.airdrop(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<AirdropRow[]> =>
      unwrap(
        await supabase
          .from('airdrop_registrations')
          .select(
            'id, event_type, voucher_type, requested_amount, status, credited_amount, tokens_credited, credited_at, admin_notes, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

export interface NewAirdropRegistration {
  fullName: string;
  emailAddress: string;
  walletAddress: string;
  requestedAmount: number;
  eventType: string;
  voucherId: string | null;
}

/**
 * Register for the airdrop. Raises a pending request and credits nothing.
 *
 * `status: 'pending'`, and no `credited_amount` or `tokens_credited`, are sent
 * explicitly rather than left to the column defaults — and that is worth
 * spelling out, because the INSERT policy on this table is only
 * `WITH CHECK (auth.uid() = user_id)`. It constrains *whose* row this is and
 * nothing about its contents, so a hand-rolled request can arrive already
 * marked approved and credited (confirmed, F-075). Compare `str_domains`, whose
 * policy is `WITH CHECK (auth.uid() = user_id AND status = 'pending')`.
 * No balance moves either way — the trigger on this table only writes history —
 * but the admin queue and this member's own "credited" figure both believe it.
 *
 * `.select('id').single()` is the F-055 rule: an insert RLS refuses does raise,
 * but reading the row back turns "wrote nothing" into a thrown error in every
 * case rather than in most of them.
 */
export function useRegisterAirdrop() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewAirdropRegistration): Promise<string> => {
      if (!userId) throw new Error('Your session has expired. Sign in again and retry.');

      const { data, error } = await supabase
        .from('airdrop_registrations')
        .insert({
          user_id: userId,
          full_name: input.fullName,
          email_address: input.emailAddress,
          wallet_address: input.walletAddress,
          requested_amount: input.requestedAmount,
          event_type: input.eventType,
          voucher_id: input.voucherId,
          status: 'pending',
        })
        .select('id')
        .single();

      if (error) throw new Error(error.message);
      if (!data) {
        throw new Error('The registration was not recorded. Nothing has been sent for review.');
      }
      return data.id;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: bk.airdrop(userId ?? 'anon') });
      void qc.invalidateQueries({ queryKey: bk.summary(userId ?? 'anon') });
    },
  });
}

/* =========================================================== referrals == */

export type ReferralRow = Pick<
  Tables['referrals']['Row'],
  'id' | 'status' | 'reward_amount' | 'reward_claimed' | 'claimed_at' | 'created_at'
>;

export interface ReferralsResult {
  rows: ReferralRow[];
  /**
   * Counted by the database, not by the length of `rows` and never by a stored
   * counter. See the note on `useAffiliateReferrals`.
   */
  total: number;
}

/**
 * The member's own referrals.
 *
 * Unlike v2 this does not fetch the referred members' profiles. v2 pulled every
 * referred user's `full_name` and `email_address` into the referrer's browser
 * to render a name column — other people's contact details, shipped to a third
 * party, to decorate a table.
 */
export function useMyReferrals() {
  const userId = useUserId();

  return useQuery({
    queryKey: bk.referrals(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<ReferralsResult> => {
      const { data, error, count } = await supabase
        .from('referrals')
        .select('id, status, reward_amount, reward_claimed, claimed_at, created_at', {
          count: 'exact',
        })
        .eq('referrer_id', userId!)
        .order('created_at', { ascending: false })
        .limit(200);

      if (error) throw new Error(error.message);
      return { rows: data ?? [], total: count ?? 0 };
    },
  });
}

export type AffiliateRow = Pick<
  Tables['seed_str_affiliates']['Row'],
  | 'id'
  | 'affiliate_code'
  | 'str_domain'
  | 'status'
  | 'usdt_address'
  | 'usdt_network'
  | 'usdc_address'
  | 'usdc_network'
  | 'total_investment_referred'
  | 'created_at'
>;

/**
 * The member's affiliate enrolment.
 *
 * `total_referrals` and `total_conversions` are deliberately not selected. v2
 * incremented `total_referrals` with a plain UPDATE from the referral landing
 * page, which ran for any anonymous visitor — so the number was whatever the
 * last person to refresh the link had made it, and reading it here would put
 * that back on screen as if it were a fact.
 */
export function useMyAffiliate() {
  const userId = useUserId();

  return useQuery({
    queryKey: bk.affiliate(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<AffiliateRow | null> =>
      unwrap(
        await supabase
          .from('seed_str_affiliates')
          .select(
            'id, affiliate_code, str_domain, status, usdt_address, usdt_network, usdc_address, usdc_network, total_investment_referred, created_at'
          )
          .eq('user_id', userId!)
          .maybeSingle()
      ),
  });
}

export type AffiliateReferralRow = Pick<
  Tables['seed_str_referrals']['Row'],
  'id' | 'status' | 'investment_amount' | 'commission_amount' | 'converted_at' | 'created_at'
>;

export interface AffiliateReferralsResult {
  rows: AffiliateReferralRow[];
  /** `count: 'exact'` — the database counts, the browser does not. */
  total: number;
  converted: number;
}

/** Referrals attributed to the affiliate code, counted server-side. */
export function useAffiliateReferrals(affiliateId: string | undefined) {
  return useQuery({
    queryKey: bk.affiliateReferrals(affiliateId ?? 'none'),
    enabled: !!affiliateId,
    queryFn: async (): Promise<AffiliateReferralsResult> => {
      const [all, converted] = await Promise.all([
        supabase
          .from('seed_str_referrals')
          .select('id, status, investment_amount, commission_amount, converted_at, created_at', {
            count: 'exact',
          })
          .eq('affiliate_id', affiliateId!)
          .order('created_at', { ascending: false })
          .limit(200),
        supabase
          .from('seed_str_referrals')
          .select('id', { count: 'exact', head: true })
          .eq('affiliate_id', affiliateId!)
          .not('converted_at', 'is', null),
      ]);

      if (all.error) throw new Error(all.error.message);
      if (converted.error) throw new Error(converted.error.message);

      return {
        rows: all.data ?? [],
        total: all.count ?? 0,
        converted: converted.count ?? 0,
      };
    },
  });
}

export interface NewAffiliate {
  fullName: string;
  email: string;
  /** The member's own main str.domain. Not a code they choose. */
  strDomain: string;
  usdtAddress: string | null;
  usdtNetwork: string | null;
  usdcAddress: string | null;
  usdcNetwork: string | null;
}

/**
 * Enrol as an affiliate.
 *
 * The affiliate code is derived from the member's own minted domain rather than
 * being typed, so it cannot collide with, or impersonate, someone else's. The
 * counters on the row are left at their defaults and are never written from
 * here.
 */
export function useCreateAffiliate() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: NewAffiliate) => {
      const code = input.strDomain.replace(/^str\./i, '').trim().toLowerCase();
      if (!code) throw new Error('A minted str.domain is required to enrol.');

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
        // 23505 is the unique violation on affiliate_code / user_id.
        throw new Error(
          error.code === '23505'
            ? 'That domain is already enrolled as an affiliate.'
            : error.message
        );
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: bk.affiliate(userId ?? 'anon') }),
  });
}

export interface PayoutAddresses {
  affiliateId: string;
  usdtAddress: string | null;
  usdtNetwork: string | null;
  usdcAddress: string | null;
  usdcNetwork: string | null;
}

/**
 * Update where commission is paid. Touches addresses and nothing else.
 *
 * This write cannot currently succeed, and the screen says so rather than
 * offering a form that quietly does nothing. `seed_str_affiliates` carries an
 * INSERT policy for the owner and SELECT policies for the owner and for
 * administrators — and no member UPDATE policy at all. PostgREST filters the
 * statement to zero rows and answers `200 []` with `error === null`, so the
 * previous version of this hook resolved successfully and the form toasted
 * "Payout addresses updated." over an address that had not moved. Confirmed
 * against a live stack: PATCH returned `[]`, and a re-read showed the original
 * address. That is finding F-055, on the field that decides where money is
 * sent. See F-078.
 *
 * The `.select('id')` and the zero-row check stay regardless of the UI, so if a
 * policy is added later this starts working and, if it is not, it fails loudly.
 *
 * TODO(server): either a `USING (auth.uid() = user_id)` UPDATE policy scoped to
 * the four address columns, or — better, since these are payout destinations —
 * a `v2_member_set_affiliate_payout(p_usdt_address, p_usdt_network,
 * p_usdc_address, p_usdc_network)` SECURITY DEFINER routine that resolves the
 * affiliate from `auth.uid()` and can write nothing else.
 */
export function useUpdatePayoutAddresses() {
  const userId = useUserId();
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (input: PayoutAddresses) => {
      const { data, error } = await supabase
        .from('seed_str_affiliates')
        .update({
          usdt_address: input.usdtAddress,
          usdt_network: input.usdtNetwork,
          usdc_address: input.usdcAddress,
          usdc_network: input.usdcNetwork,
        })
        .eq('id', input.affiliateId)
        .select('id');
      if (error) throw new Error(error.message);
      if (!data || data.length === 0) {
        throw new Error(
          'The addresses were not changed. The database refused the update — there is no policy that lets a member edit their own affiliate payout addresses. Raise a support ticket to have them changed.'
        );
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: bk.affiliate(userId ?? 'anon') }),
  });
}

/* =============================================================== admin == */

/**
 * Voucher statuses that release tokens.
 *
 * Moving a voucher to one of these runs the crediting branch inside
 * `process_voucher_redemption_with_audit`, so it is gated on safe mode.
 * Everything else is a review decision that moves no value.
 */
export const CREDITING_VOUCHER_STATUSES = ['approved', 'completed', 'credited'] as const;

export function isCreditingStatus(status: string): boolean {
  return (CREDITING_VOUCHER_STATUSES as readonly string[]).includes(status);
}

export type AdminVoucherRow = Pick<
  Tables['voucher_redemptions']['Row'],
  | 'id'
  | 'user_id'
  | 'full_name'
  | 'email_address'
  | 'token_type'
  | 'package_type'
  | 'payment_type'
  | 'payment_hash'
  | 'confirmation_number'
  | 'amount'
  | 'status'
  | 'credited_amount'
  | 'tokens_credited'
  | 'credited_at'
  | 'admin_notes'
  | 'created_at'
>;

/** The review queue. `status` of 'all' lifts the filter. */
export function useAdminVouchers(status: string) {
  return useQuery({
    queryKey: bk.admin('vouchers', status),
    queryFn: async (): Promise<AdminVoucherRow[]> => {
      let q = supabase
        .from('voucher_redemptions')
        .select(
          'id, user_id, full_name, email_address, token_type, package_type, payment_type, payment_hash, confirmation_number, amount, status, credited_amount, tokens_credited, credited_at, admin_notes, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

export type VoucherHistoryRow = Pick<
  Tables['voucher_redemption_history']['Row'],
  'id' | 'action_performed' | 'status_from' | 'status_to' | 'admin_notes' | 'performed_by' | 'created_at'
>;

/** The audit trail for one voucher. */
export function useVoucherHistory(voucherId: string | null) {
  return useQuery({
    queryKey: bk.adminVoucherHistory(voucherId ?? 'none'),
    enabled: !!voucherId,
    queryFn: async (): Promise<VoucherHistoryRow[]> =>
      unwrap(
        await supabase
          .from('voucher_redemption_history')
          .select('id, action_performed, status_from, status_to, admin_notes, performed_by, created_at')
          .eq('voucher_redemption_id', voucherId!)
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

export type CorrectionQueueRow = Pick<
  Tables['voucher_corrections']['Row'],
  | 'id'
  | 'voucher_id'
  | 'full_name'
  | 'token_type'
  | 'package_type'
  | 'previous_amount'
  | 'corrected_amount'
  | 'difference'
  | 'correction_type'
  | 'correction_reason'
  | 'corrected_at'
>;

/** Every restatement applied, newest first. */
export function useAdminCorrections() {
  return useQuery({
    queryKey: bk.admin('corrections', 'all'),
    queryFn: async (): Promise<CorrectionQueueRow[]> =>
      unwrap(
        await supabase
          .from('voucher_corrections')
          .select(
            'id, voucher_id, full_name, token_type, package_type, previous_amount, corrected_amount, difference, correction_type, correction_reason, corrected_at'
          )
          .order('corrected_at', { ascending: false })
          .limit(200)
      ) ?? [],
  });
}

export type VoucherErrorRow = Pick<
  Tables['voucher_error_log']['Row'],
  'id' | 'error_type' | 'error_message' | 'voucher_redemption_id' | 'created_at'
>;

/**
 * Failures the voucher pipeline recorded.
 *
 * `stack_trace`, `user_agent` and `ip_address` are on this table and are not
 * selected: an operator triaging a failed credit does not need the claimant's
 * IP address in their browser.
 */
export function useVoucherErrors() {
  return useQuery({
    queryKey: bk.admin('errors', 'all'),
    queryFn: async (): Promise<VoucherErrorRow[]> =>
      unwrap(
        await supabase
          .from('voucher_error_log')
          .select('id, error_type, error_message, voucher_redemption_id, created_at')
          .order('created_at', { ascending: false })
          .limit(100)
      ) ?? [],
  });
}

export type AdminAirdropRow = Pick<
  Tables['airdrop_registrations']['Row'],
  | 'id'
  | 'user_id'
  | 'full_name'
  | 'event_type'
  | 'requested_amount'
  | 'status'
  | 'credited_amount'
  | 'tokens_credited'
  | 'credited_at'
  | 'admin_notes'
  | 'created_at'
>;

export function useAdminAirdrops(status: string) {
  return useQuery({
    queryKey: bk.admin('airdrops', status),
    queryFn: async (): Promise<AdminAirdropRow[]> => {
      let q = supabase
        .from('airdrop_registrations')
        .select(
          'id, user_id, full_name, event_type, requested_amount, status, credited_amount, tokens_credited, credited_at, admin_notes, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(200);
      if (status !== 'all') q = q.eq('status', status);
      return unwrap(await q) ?? [];
    },
  });
}

/* --------------------------------------------------------- admin writes */

function useInvalidateAdmin() {
  const qc = useQueryClient();
  return () => {
    void qc.invalidateQueries({ queryKey: bk.adminAll });
  };
}

/**
 * Move a voucher to a new status.
 *
 * `process_voucher_redemption_with_audit` performs the status change, the
 * credit and the audit entry in one database call — which is the entire point.
 * v2's admin screen did the same job by reading `arss_balance`, adding the
 * voucher amount in JavaScript and writing the sum back, so approving two
 * vouchers in the same second credited one of them.
 *
 * `performed_by_user_id` is attribution, not authorisation: the route guard is
 * a UI convenience and the function is expected to check `auth.uid()` itself.
 *
 * Gated on safe mode when the target status releases tokens. The check is
 * inside the mutation, so it holds even if a caller skips the disabled button.
 */
export function useReviewVoucher() {
  const userId = useUserId();
  const invalidate = useInvalidateAdmin();

  return useMutation({
    mutationFn: async (input: { voucherId: string; status: string; notes?: string }) => {
      if (isCreditingStatus(input.status)) {
        assertCreditingAllowed(`set voucher to ${input.status}`);
      }
      const { error } = await supabase.rpc('process_voucher_redemption_with_audit', {
        voucher_id: input.voucherId,
        new_status: input.status,
        performed_by_user_id: userId!,
        admin_notes_param: input.notes,
        user_agent_param: navigator.userAgent,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

/** Recompute one voucher's token amount from the server's package table. */
export function useCorrectVoucherTokens() {
  const userId = useUserId();
  const invalidate = useInvalidateAdmin();

  return useMutation({
    mutationFn: async (voucherId: string) => {
      assertCreditingAllowed('recompute voucher tokens');
      const { error } = await supabase.rpc('admin_correct_voucher_tokens', {
        voucher_id_param: voucherId,
        admin_user_id: userId!,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

/** Restate one voucher to an explicit amount, with the reason recorded. */
export function useCorrectVoucherAmount() {
  const invalidate = useInvalidateAdmin();

  return useMutation({
    mutationFn: async (input: { voucherId: string; amount: number; reason: string }) => {
      assertCreditingAllowed('restate voucher amount');
      if (!Number.isFinite(input.amount) || input.amount < 0) {
        throw new Error('Enter a corrected amount of zero or more.');
      }
      if (!input.reason.trim()) {
        throw new Error('A correction reason is required.');
      }
      const { error } = await supabase.rpc('correct_voucher_amount', {
        p_voucher_id: input.voucherId,
        p_corrected_amount: input.amount,
        p_correction_reason: input.reason.trim(),
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: invalidate,
  });
}

export type SweepJob = 'correct-precex-vouchers' | 'correct-str-vouchers-targeted';

export interface SweepResult {
  success?: boolean;
  dryRun?: boolean;
  total_scanned?: number;
  total_corrections?: number;
  error?: string;
}

/**
 * Call an edge function with the caller's own JWT attached.
 *
 * Identity comes from the token, never from a field in the body. A `user_id`
 * the client chooses is a client that can act as somebody else.
 */
async function invokeAsUser<T extends { success?: boolean; error?: string }>(
  name: string,
  body: Record<string, unknown>
): Promise<T> {
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw new Error(sessionError.message);
  const accessToken = sessionData.session?.access_token;
  if (!accessToken) throw new Error('Your session has expired. Sign in again and retry.');

  const { data, error } = await supabase.functions.invoke<T>(name, {
    body,
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (error) throw new Error(error.message);
  if (!data) throw new Error(`${name} returned no response.`);
  if (data.success === false) throw new Error(data.error ?? `${name} failed.`);
  return data;
}

/**
 * Bulk voucher repair.
 *
 * Both jobs run under the service role inside the edge function, which
 * re-checks the caller's role before touching anything. A dry run reports what
 * it would change and writes nothing, so it is allowed while safe mode holds;
 * an applied sweep is not.
 *
 * `correct-str-vouchers-targeted` has no dry-run mode — it applies a fixed list
 * of voucher ids — so it is always treated as a crediting action.
 */
export function useVoucherSweep() {
  const invalidate = useInvalidateAdmin();

  return useMutation({
    mutationFn: async (input: { job: SweepJob; dryRun: boolean }): Promise<SweepResult> => {
      const isDryRun = input.job === 'correct-precex-vouchers' && input.dryRun;
      if (!isDryRun) assertCreditingAllowed(`run ${input.job}`);

      return invokeAsUser<SweepResult>(
        input.job,
        input.job === 'correct-precex-vouchers' ? { dryRun: input.dryRun } : {}
      );
    },
    onSuccess: invalidate,
  });
}

/**
 * Decline or hold an airdrop registration.
 *
 * Status only. There is no crediting branch here and there cannot be one: see
 * the TODO(server) on the approve control in Admin.tsx.
 *
 * The UPDATE is checked by what came back, not by the absence of an error. The
 * only UPDATE policy on `airdrop_registrations` is
 * `USING has_role(auth.uid(), 'admin')`, so a caller without the role is
 * filtered to zero rows and PostgREST answers `200 []` with `error === null` —
 * confirmed against a live project. Without the `.select('id')` below this
 * function toasted "registration declined" at a member whose decision the
 * database had refused, which is finding F-055 exactly.
 */
export function useSetAirdropStatus() {
  const invalidate = useInvalidateAdmin();

  return useMutation({
    mutationFn: async (input: { id: string; status: string; notes?: string }) => {
      if (isCreditingStatus(input.status)) {
        throw new Error('Airdrop tokens cannot be released from this screen.');
      }
      const { data, error } = await supabase
        .from('airdrop_registrations')
        .update({ status: input.status, admin_notes: input.notes ?? null })
        .eq('id', input.id)
        .select('id');
      if (error) throw new Error(error.message);
      if (!data || data.length === 0) {
        throw new Error(
          'The registration was not changed. The database refused the update — check you still hold the admin role.'
        );
      }
    },
    onSuccess: invalidate,
  });
}
