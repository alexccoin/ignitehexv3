import { supabase } from './supabase';
import type { Database } from './database.types';

/**
 * The single definition of what a balance is.
 *
 * v2 had three, and they disagreed for the same account:
 *   - WalletPage totalled `balance + staked_amount`, and for wSTR also added
 *     `rewards_earned`.
 *   - useV2Balances summed the pools and then overwrote the result with the
 *     get_available_balance RPC.
 *   - DomeOverview used `staked_amount || balance`, so a pool with nothing
 *     staked (staked_amount = 0, falsy) counted its liquid balance as staked.
 *
 * Everything below is derived from one shape, so the wallet, the dashboard and
 * the console cannot drift apart again.
 */

export type StakingPool = Database['public']['Tables']['user_staking_pools']['Row'];

/** The escrow rows a member holds. Only `locked` ones are a live claim. */
export type EscrowRow = Pick<
  Database['public']['Tables']['marketplace_escrow_balances']['Row'],
  'asset_symbol' | 'amount' | 'status'
>;

export interface TokenPosition {
  token: string;
  /**
   * `user_staking_pools.balance` — the live holding, and the only column the
   * server treats as spendable (`get_available_balance` is SUM(balance)).
   */
  liquid: number;
  /**
   * `user_staking_pools.staked_amount` — the principal AS FIRST CREDITED, and
   * NOT a second holding. See the note on `total` below.
   */
  staked: number;
  /** Accrued but not yet withdrawn. */
  rewards: number;
  /** Locked in marketplace escrow: sold but not yet settled. */
  escrowed: number;
  /** liquid + escrowed. What the member actually has. See below. */
  total: number;
  /** Whether the available figure came back from the server. */
  available: number | null;
}

const num = (v: unknown): number => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
};

/**
 * Fold a user's staking pool rows into one position per token.
 *
 * `staked_amount` and `balance` are read as independent numbers - never as a
 * fallback for one another, which is what produced the v2 miscount.
 *
 * WHY `total` NO LONGER ADDS `staked` OR `rewards` (F-032)
 *
 * It used to be `liquid + staked + rewards`, on the reading that the three
 * columns are three disjoint buckets. They are not. Measured against
 * production, 2026-08-19:
 *
 *   - `credit_voucher_tokens` writes the SAME quantity into `balance` and
 *     `staked_amount` for one redemption. One credit, two columns, same number.
 *   - `calculate_daily_rewards` then adds each reward to `rewards_earned` AND
 *     to `balance`, and never to `staked_amount`.
 *   - `get_available_balance` — the server's own answer for what is spendable —
 *     is `SUM(balance)`, nothing else.
 *   - Across 56,836 production rows, `balance = staked_amount` on 54,499 of
 *     them. Joined to what the vouchers actually credited, `balance + staked`
 *     reconciled 166 times out of 4,515 while each column alone reconciled
 *     1,108 and 1,534 times.
 *
 * So `staked_amount` is the principal as first credited and `balance` is the
 * same tokens live; `rewards_earned` is already inside `balance`. Adding them
 * counted one holding two and three times. investor1 held 13,184 STR and this
 * function reported 26,834.
 *
 * `total` is now `liquid + escrowed` — what the member has, plus what is out
 * of their hands in a marketplace lock but still theirs. `staked` and
 * `rewards` are still returned and still shown under their own labels, where
 * they are true statements: how much principal was staked, and how much has
 * accrued.
 */
export function positionsFromPools(
  pools: StakingPool[],
  escrow: EscrowRow[] = []
): TokenPosition[] {
  const byToken = new Map<string, TokenPosition>();

  const entryFor = (token: string): TokenPosition => {
    let entry = byToken.get(token);
    if (!entry) {
      entry = { token, liquid: 0, staked: 0, rewards: 0, escrowed: 0, total: 0, available: null };
      byToken.set(token, entry);
    }
    return entry;
  };

  for (const pool of pools) {
    const entry = entryFor((pool.pool_type ?? 'unknown').toLowerCase());
    entry.liquid += num(pool.balance);
    entry.staked += num(pool.staked_amount);
    entry.rewards += num(pool.rewards_earned);
  }

  for (const row of escrow) {
    if (row.status !== 'locked') continue;
    entryFor((row.asset_symbol ?? 'unknown').toLowerCase()).escrowed += num(row.amount);
  }

  for (const entry of byToken.values()) {
    entry.total = entry.liquid + entry.escrowed;
  }

  return [...byToken.values()].sort((a, b) => b.total - a.total);
}

/**
 * Ask the server what is actually spendable.
 *
 * A failed lookup returns null, not zero. v2 collapsed both to 0, so a
 * transient error was indistinguishable from an empty wallet - and because the
 * wallet page then computed `locked = total - available`, one failed request
 * displayed the user's entire holding as locked.
 */
export async function fetchAvailable(userId: string, token: string): Promise<number | null> {
  const { data, error } = await supabase.rpc('get_available_balance', {
    p_user_id: userId,
    p_token_type: token,
  } as never);

  if (error || data === null || data === undefined) return null;
  const n = Number(data);
  return Number.isFinite(n) ? n : null;
}

/**
 * The largest single position.
 *
 * Deliberately NOT a sum across tokens. Adding STR to CCOS to DOMAIN produces a
 * number with no unit, and there is no honest way to convert them to a common
 * one: the platform's own price feed (supabase/functions/str-price) returns
 * Math.random() between 0.028 and 0.0318, so a "total portfolio value" built on
 * it would be fiction. A headline figure has to be something true, so it is the
 * biggest holding, named in its own token.
 *
 * If a real priced total is wanted later, it needs a trustworthy oracle first —
 * then sum the USD values, never the raw quantities.
 */
export function largestPosition(positions: TokenPosition[]): TokenPosition | null {
  return positions.length ? positions.reduce((a, b) => (b.total > a.total ? b : a)) : null;
}

/**
 * Render a per-token figure without inventing a common unit.
 *
 * Summing STR + CCOS + DOMAIN produces a number with no unit, and there is no
 * honest conversion available: the platform's own price endpoint returns
 * Math.random(). This bug has now been introduced three times — once per
 * "total" tile someone reasonably wanted — so the fix is to make the wrong
 * thing unavailable rather than to correct each site.
 *
 * One token  -> "23,542 CCOS"
 * Two        -> "23,542 CCOS · 500 STR"
 * More       -> "23,542 CCOS · 500 STR +2 more"
 *
 * `field` picks which side of the position to read, so the same helper serves
 * the holdings, staked and rewards tiles.
 */
export function byToken(
  positions: TokenPosition[],
  field: 'total' | 'liquid' | 'staked' | 'rewards' | 'escrowed',
  fmt: (amount: number, token: string) => string,
  maxShown = 2
): string {
  return byUnit(
    positions.map((p) => ({ unit: p.token, amount: p[field] })),
    fmt,
    maxShown
  );
}

/**
 * The same rule for anything else that carries a unit.
 *
 * `byToken` reads staking positions; ledger rows, fiat wallets and reward
 * credits carry a `currency` instead, and adding those together is the same
 * defect wearing a different column name. Entries sharing a unit are folded
 * together first, so two EUR rows read "1,500 EUR", not "1,000 EUR · 500 EUR".
 */
export function byUnit(
  entries: Iterable<{ unit: string; amount: number }>,
  fmt: (amount: number, unit: string) => string,
  maxShown = 2
): string {
  const folded = new Map<string, number>();
  for (const { unit, amount } of entries) {
    const n = num(amount);
    if (n <= 0) continue;
    folded.set(unit, (folded.get(unit) ?? 0) + n);
  }

  const held = [...folded.entries()].sort((a, b) => b[1] - a[1]);
  if (held.length === 0) return '—';

  const shown = held.slice(0, maxShown).map(([unit, amount]) => fmt(amount, unit));
  const rest = held.length - shown.length;
  return shown.join(' · ') + (rest > 0 ? ` +${rest} more` : '');
}
