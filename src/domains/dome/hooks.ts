import { useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import { shortDate } from '@/lib/format';
import type { Database } from '@/lib/database.types';

/**
 * Every read and write the Dome domain performs.
 *
 * The Dome prototype this screen comes from was a static mock: one member's
 * domain, one member's serial, one member's earnings, all typed into the
 * markup. `31,250 shares`, `$93,750 estimated value`, `+87.5% vs public` and
 * `0.094% of supply` were literals in JSX, so every visitor saw the same
 * portfolio regardless of what they actually owned.
 *
 * Nothing here is a literal. Equity comes from `safe_purchases`,
 * `private_digital_shares_purchases` and `user_str_shares`; token positions
 * come from the shared balance hooks; notices come from `user_messages`. Where
 * the prototype had a figure and the database has no column for it, the panel
 * renders an empty state instead of a number — see `hasPricedRound` below and
 * the "no data source" notes in Overview.tsx and Portfolio.tsx.
 *
 * The one number in this file that is not read from a row is TOTAL_SUPPLY, and
 * it is named, exported, and printed on screen next to every percentage derived
 * from it so the denominator is never hidden.
 */

type Tables = Database['public']['Tables'];

export type SafeAllocation = Pick<
  Tables['safe_purchases']['Row'],
  | 'id'
  | 'total_shares'
  | 'bonus_shares'
  | 'bonus_pct'
  | 'credited_shares'
  | 'total_usd'
  | 'price_per_share_usd'
  | 'status'
  | 'credited_at'
  | 'created_at'
  | 'tx_hash'
>;

export type ShareLedger = Pick<
  Tables['user_str_shares']['Row'],
  'id' | 'balance' | 'locked_balance' | 'wnft_shares' | 'vesting_end_date' | 'updated_at'
>;

export type DigitalSharePurchase = Pick<
  Tables['private_digital_shares_purchases']['Row'],
  | 'id'
  | 'shares_quantity'
  | 'price_per_share'
  | 'total_usd'
  | 'payment_status'
  | 'wnft_status'
  | 'payment_hash'
  | 'created_at'
>;

export type VestingSchedule = Pick<
  Tables['vesting_tokens']['Row'],
  | 'id'
  | 'amount'
  | 'token_type'
  | 'source'
  | 'status'
  | 'vesting_start_date'
  | 'vesting_end_date'
  | 'vesting_months'
  | 'released_at'
>;

export type CryptoWallet = Pick<
  Tables['crypto_wallets']['Row'],
  'id' | 'token_type' | 'balance' | 'available_balance' | 'held_balance'
>;

export type ArssWallet = Pick<
  Tables['user_wallets']['Row'],
  'id' | 'arss_balance' | 'total_earned' | 'total_spent' | 'wallet_address'
>;

export type Notice = Pick<
  Tables['user_messages']['Row'],
  'id' | 'subject' | 'message' | 'message_type' | 'is_read' | 'read_at' | 'created_at'
>;

/**
 * Query keys for this domain, namespaced under 'dome'.
 *
 * Deliberately distinct from `qk.*`: the shared hooks in `src/hooks/data.ts`
 * cache their own tables with their own column lists, and two queries sharing a
 * key while selecting different columns means whichever ran first wins and the
 * other silently reads a row missing half its fields.
 */
export const dk = {
  all: ['dome'] as const,
  allocations: (userId: string) => ['dome', 'safe-allocations', userId] as const,
  ledger: (userId: string) => ['dome', 'share-ledger', userId] as const,
  digital: (userId: string) => ['dome', 'digital-shares', userId] as const,
  vesting: (userId: string) => ['dome', 'vesting', userId] as const,
  crypto: (userId: string) => ['dome', 'crypto-wallets', userId] as const,
  arss: (userId: string) => ['dome', 'arss-wallet', userId] as const,
  reach: (userId: string) => ['dome', 'reach', userId] as const,
  notices: (userId: string) => ['dome', 'notices', userId] as const,
} as const;

/**
 * Total share supply the ownership percentage is measured against.
 *
 * Carried over from the v2 Dome pages. It is a platform constant rather than a
 * per-member figure, and there is no table that publishes it, so it is exported
 * and rendered beside every percentage it produces instead of being buried in a
 * calculation. If it ever moves into the database, this is the only line that
 * changes.
 */
export const TOTAL_SUPPLY = 33_250_000;

/** Payment states that mean the allocation never completed. */
const NOT_SETTLED = /failed|cancell?ed|expired|refunded|rejected/i;

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

/** SAFE allocations recorded against the signed-in member. */
export function useSafeAllocations() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.allocations(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<SafeAllocation[]> =>
      unwrap(
        await supabase
          .from('safe_purchases')
          .select(
            'id, total_shares, bonus_shares, bonus_pct, credited_shares, total_usd, price_per_share_usd, status, credited_at, created_at, tx_hash'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

/**
 * The member's $STR share ledger row.
 *
 * `maybeSingle` because a member who has never been allocated anything has no
 * row at all — which is a legitimate empty state, not an error.
 */
export function useShareLedger() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.ledger(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<ShareLedger | null> =>
      unwrap(
        await supabase
          .from('user_str_shares')
          .select('id, balance, locked_balance, wnft_shares, vesting_end_date, updated_at')
          .eq('user_id', userId!)
          .maybeSingle()
      ),
  });
}

/** Private digital share placements. */
export function useDigitalShares() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.digital(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<DigitalSharePurchase[]> =>
      unwrap(
        await supabase
          .from('private_digital_shares_purchases')
          .select(
            'id, shares_quantity, price_per_share, total_usd, payment_status, wnft_status, payment_hash, created_at'
          )
          .eq('user_id', userId!)
          .order('created_at', { ascending: false })
      ) ?? [],
  });
}

/** Locked allocations releasing into the member's staking pools. */
export function useVestingSchedules() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.vesting(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<VestingSchedule[]> =>
      unwrap(
        await supabase
          .from('vesting_tokens')
          .select(
            'id, amount, token_type, source, status, vesting_start_date, vesting_end_date, vesting_months, released_at'
          )
          .eq('user_id', userId!)
          .order('vesting_end_date', { ascending: true })
      ) ?? [],
  });
}

/** Non-STR token balances. */
export function useCryptoWallets() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.crypto(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<CryptoWallet[]> =>
      unwrap(
        await supabase
          .from('crypto_wallets')
          .select('id, token_type, balance, available_balance, held_balance')
          .eq('user_id', userId!)
          .order('token_type')
      ) ?? [],
  });
}

/** The ARSS wallet, which lives on its own table rather than in a pool. */
export function useArssWallet() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.arss(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<ArssWallet | null> =>
      unwrap(
        await supabase
          .from('user_wallets')
          .select('id, arss_balance, total_earned, total_spent, wallet_address')
          .eq('user_id', userId!)
          .maybeSingle()
      ),
  });
}

/**
 * How far the member's file reaches across the platform: str.name domains held
 * and how many of them are currently listed.
 *
 * Head counts rather than row fetches — the panel shows two integers and has no
 * use for the rows behind them.
 */
export function useDomeReach() {
  const userId = useUserId();
  return useQuery({
    queryKey: dk.reach(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async (): Promise<{ domains: number; listings: number }> => {
      const [domains, listings] = await Promise.all([
        supabase
          .from('str_domains')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', userId!),
        supabase
          .from('domain_marketplace_listings')
          .select('id', { count: 'exact', head: true })
          .eq('seller_id', userId!)
          .eq('status', 'active'),
      ]);
      if (domains.error) throw new Error(domains.error.message);
      if (listings.error) throw new Error(listings.error.message);
      return { domains: domains.count ?? 0, listings: listings.count ?? 0 };
    },
  });
}

/**
 * Messages addressed to the member.
 *
 * This replaces the prototype's notifications dropdown, whose three entries
 * ("Q1 2027 Dividend Confirmed — $12.4M distributed", "eSIM Beta Now Live",
 * "Public Round Announced — Price: $3.00") were hardcoded announcements with no
 * table behind them.
 */
export function useNotices(limit = 8) {
  const userId = useUserId();
  return useQuery({
    queryKey: [...dk.notices(userId ?? 'anon'), limit],
    enabled: !!userId,
    queryFn: async (): Promise<Notice[]> =>
      unwrap(
        await supabase
          .from('user_messages')
          .select('id, subject, message, message_type, is_read, read_at, created_at')
          .eq('recipient_id', userId!)
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/* -------------------------------------------------------------- mutations */

/**
 * Mark a notice as read.
 *
 * The only write in this domain, and deliberately so: it touches a read flag,
 * not a balance. The `recipient_id` predicate is belt-and-braces next to RLS —
 * a client that could name another row would be a client that can mark someone
 * else's mail as read.
 */
export function useMarkNoticeRead() {
  const qc = useQueryClient();
  const userId = useUserId() ?? 'anon';
  return useMutation({
    mutationFn: async (noticeId: string) => {
      const { error } = await supabase
        .from('user_messages')
        .update({ is_read: true, read_at: new Date().toISOString() })
        .eq('id', noticeId)
        .eq('recipient_id', userId);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: dk.notices(userId) });
    },
  });
}

/* ------------------------------------------------------------ derivations */

/** One equity allocation, whichever programme it was booked under. */
export interface AllocationRecord {
  id: string;
  programme: string;
  date: string;
  shares: number;
  bonusShares: number;
  pricePerShare: number;
  invested: number;
  status: string;
  /** Whether this record counts toward the totals. */
  counted: boolean;
  reference: string | null;
}

export interface EquityMetrics {
  /** Every record, newest first — including the ones that never settled. */
  records: AllocationRecord[];
  /** Settled records only, oldest first. */
  counted: AllocationRecord[];
  safeShares: number;
  digitalShares: number;
  wnftShares: number;
  /** safeShares + digitalShares + wnftShares. */
  shares: number;
  invested: number;
  /** invested / shares, or 0 when either is 0. */
  avgPrice: number;
  /** Price per share on the most recent settled record. */
  latestPrice: number;
  /** latestPrice when there is one, otherwise avgPrice. */
  price: number;
  value: number;
  unrealised: number;
  /** null when nothing has been invested — a ratio with a zero denominator. */
  roi: number | null;
  /** Percentage of TOTAL_SUPPLY. */
  ownership: number;
  /** Shares the same money would have bought at `latestPrice`. */
  publicEquivalent: number;
  extraShares: number;
  /** null when there is no priced round to compare against. */
  extraPct: number | null;
  /** Cumulative invested value over time, for the trend chart. */
  cumulative: { label: string; value: number }[];
  strLiquid: number;
  strLocked: number;
  hasEquity: boolean;
  /** Whether a price per share has ever been recorded for this member. */
  hasPricedRound: boolean;
}

const num = (v: unknown): number => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
};

/**
 * Fold the three equity sources into one set of figures.
 *
 * Two decisions worth stating:
 *
 *  - A record whose payment failed, expired or was cancelled is kept in
 *    `records` so the member can see it, but excluded from every total. The
 *    prototype had no concept of an unsettled allocation at all.
 *  - wNFT shares add to the share count but not to `invested`, because the
 *    ledger row carries no cost basis. That makes `avgPrice` a blended figure
 *    across paid shares only, which is why it is labelled "avg paid" on screen
 *    rather than "cost basis".
 */
export function computeEquity(
  safe: SafeAllocation[],
  ledger: ShareLedger | null,
  digital: DigitalSharePurchase[]
): EquityMetrics {
  const safeRecords: AllocationRecord[] = safe.map((row) => ({
    id: `safe-${row.id}`,
    programme: 'SAFE',
    date: row.credited_at ?? row.created_at,
    shares: num(row.credited_shares ?? row.total_shares),
    bonusShares: num(row.bonus_shares),
    pricePerShare: num(row.price_per_share_usd),
    invested: num(row.total_usd),
    status: row.credited_at ? 'credited' : row.status,
    counted: !NOT_SETTLED.test(row.status ?? ''),
    reference: row.tx_hash || null,
  }));

  const digitalRecords: AllocationRecord[] = digital.map((row) => ({
    id: `digital-${row.id}`,
    programme: 'Private placement',
    date: row.created_at,
    shares: num(row.shares_quantity),
    bonusShares: 0,
    pricePerShare: num(row.price_per_share),
    invested: num(row.total_usd),
    status: row.payment_status,
    counted: !NOT_SETTLED.test(row.payment_status ?? ''),
    reference: row.payment_hash || null,
  }));

  const records = [...safeRecords, ...digitalRecords]
    .filter((r) => !!r.date)
    .sort((a, b) => +new Date(b.date) - +new Date(a.date));
  const counted = [...records].filter((r) => r.counted).reverse();

  const safeShares = safeRecords
    .filter((r) => r.counted)
    .reduce((sum, r) => sum + r.shares + r.bonusShares, 0);
  const digitalShares = digitalRecords
    .filter((r) => r.counted)
    .reduce((sum, r) => sum + r.shares, 0);
  const wnftShares = num(ledger?.wnft_shares);
  const shares = safeShares + digitalShares + wnftShares;

  const invested = counted.reduce((sum, r) => sum + r.invested, 0);
  const priced = counted.filter((r) => r.pricePerShare > 0);
  const latestPrice = priced.length ? priced[priced.length - 1].pricePerShare : 0;
  const avgPrice = shares > 0 && invested > 0 ? invested / shares : 0;
  const price = latestPrice > 0 ? latestPrice : avgPrice;
  const value = shares * price;
  const unrealised = value - invested;
  const roi = invested > 0 ? (unrealised / invested) * 100 : null;
  const ownership = (shares / TOTAL_SUPPLY) * 100;

  const publicEquivalent = invested > 0 && latestPrice > 0 ? invested / latestPrice : 0;
  const extraShares = publicEquivalent > 0 ? Math.max(shares - publicEquivalent, 0) : 0;
  const extraPct = publicEquivalent > 0 ? (extraShares / publicEquivalent) * 100 : null;

  let running = 0;
  const cumulative = counted.map((r) => {
    running += r.invested;
    return { label: shortDate(r.date), value: running };
  });

  return {
    records,
    counted,
    safeShares,
    digitalShares,
    wnftShares,
    shares,
    invested,
    avgPrice,
    latestPrice,
    price,
    value,
    unrealised,
    roi,
    ownership,
    publicEquivalent,
    extraShares,
    extraPct,
    cumulative,
    strLiquid: num(ledger?.balance),
    strLocked: num(ledger?.locked_balance),
    hasEquity: shares > 0,
    hasPricedRound: latestPrice > 0,
  };
}

/**
 * The equity picture, composed from its three sources.
 *
 * Exposed as one loading/error surface so a page never renders half a portfolio
 * — a share count that has arrived next to an invested total that has not is
 * how a member reads a 100% loss that is not there.
 */
export function useDomeEquity() {
  const safe = useSafeAllocations();
  const ledger = useShareLedger();
  const digital = useDigitalShares();

  const metrics = useMemo(
    () => computeEquity(safe.data ?? [], ledger.data ?? null, digital.data ?? []),
    [safe.data, ledger.data, digital.data]
  );

  return {
    metrics,
    isLoading: safe.isLoading || ledger.isLoading || digital.isLoading,
    isError: safe.isError || ledger.isError || digital.isError,
    error: safe.error ?? ledger.error ?? digital.error,
    refetch: () => {
      void safe.refetch();
      void ledger.refetch();
      void digital.refetch();
    },
  };
}
