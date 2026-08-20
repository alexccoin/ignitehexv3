import { supabase } from '@/lib/supabase';
import { paginate, type PageResponse } from './paginate';
import { checkCoverage, type CoverageReport } from './coverage';
import { fetchBtcPriceUsd } from '@/lib/btcPrice';
import { fetchEthPriceUsd } from '@/lib/ethPrice';
import {
  isCredited,
  isDead,
  num,
  round2,
  tokenUsd,
  unitLabel,
  usdFromPackage,
  voucherTokens,
  type MarketRates,
} from './valuation';

/**
 * Platform-wide member exposure index.
 *
 * Ported from v2 `src/lib/platformExposure.ts`. Builds ONE USD-valued exposure
 * record per member by sweeping every asset-bearing table in the database —
 * vouchers, fiat, IBANs, crypto, ARSS wallets, staking, $STR shares, vesting,
 * SAFE equity, seed / IPO / pre-listing / digital-share subscriptions, CCOS and
 * ARSS purchases, STARW and supernodes, guardian vaults and prepaid cards.
 *
 * Read-only. Nothing here mutates anything.
 *
 * What changed in the port, and why:
 *
 *  1. v2 ran every query through `const anyDb = supabase as any`, so a renamed
 *     or dropped column produced a runtime error inside a financial sweep
 *     instead of a compile error. Every read here is a typed call against the
 *     generated schema with an explicit column list.
 *  2. v2 paged with `.order('created_at', { ascending: false })`. `created_at`
 *     is not unique — rows sharing a timestamp can be returned on two pages or
 *     on neither as the window moves. Paging is by `id` ascending, which is
 *     unique, so a member cannot be double-counted or missed.
 *  3. v2 stopped after 40 pages and said nothing. Hitting the page budget is
 *     now reported as `truncatedTables`, because a silently short read
 *     understates exposure, and understating exposure is the one failure this
 *     file exists to prevent.
 *  4. STR is priced from a constant rather than v2's random "hardened" price.
 *     See lib/valuation.ts.
 *  5. NOT EVERY HOLDING HAS A USD VALUE, and the ones that do not are no longer
 *     given one. EUR, CHF and GBP used to be counted as 1.00 USD each, so
 *     `moderator CHF 19,903.44` was reported as `US$19,903.44` and the platform
 *     total added four currencies together under a US$ heading. Any symbol
 *     without a rate - the three foreign currencies, `domain` and `estr` pools,
 *     BTC or ETH when their price feed is down - is now accumulated as an
 *     unconverted quantity in `unpriced`, excluded from `totalUsd`, and
 *     reported beside it in its own unit. There is no FX source in this system,
 *     and inventing one would be a worse answer than saying so.
 */

/** Minimum USD exposure for a member to appear on the risk list. */
export const MIN_EXPOSURE_USD = 10_000;

/** Thresholds the caller may offer as a filter. */
export const EXPOSURE_THRESHOLDS = [10_000, 25_000, 100_000, 250_000, 1_000_000] as const;

export type ExposureLevel = 'critical' | 'high' | 'medium' | 'low';

export interface ExposureBreakdown {
  pendingVouchers: number;
  fiat: number;
  crypto: number;
  staking: number;
  shares: number;
  vesting: number;
  safeEquity: number;
  subscriptions: number;
  nodes: number;
  guardian: number;
  cards: number;
}

/** A quantity that has no USD rate, kept in the unit it is denominated in. */
export interface UnpricedAmount {
  unit: string;
  amount: number;
}

/** Human labels for the breakdown keys, used by the composition chart. */
export const BREAKDOWN_LABELS: Record<keyof ExposureBreakdown, string> = {
  pendingVouchers: 'Vouchers',
  fiat: 'Fiat',
  crypto: 'Crypto',
  staking: 'Staking',
  shares: 'Shares',
  vesting: 'Vesting',
  safeEquity: 'SAFE',
  subscriptions: 'Raises',
  nodes: 'Nodes',
  guardian: 'Vaults',
  cards: 'Cards',
};

export const BREAKDOWN_KEYS = Object.keys(BREAKDOWN_LABELS) as (keyof ExposureBreakdown)[];

export interface ExposureRow {
  userId: string;
  name: string;
  email: string;
  domain: string;
  accountStatus: string;
  totalUsd: number;
  breakdown: ExposureBreakdown;
  voucherCount: number;
  uncreditedCount: number;
  pendingTokens: number;
  /** USD value of positions an admin actually credited — the only truth. */
  adminCreditedUsd: number;
  /** Raw staking + shares + vesting USD as stored in the tables. */
  positionsUsd: number;
  /** Positions with no admin credit behind them — excluded from totalUsd. */
  unbackedUsd: number;
  /**
   * Holdings with no USD rate, per unit, EXCLUDED from `totalUsd`.
   *
   * A member holding CHF 19,903.44 and nothing else now has `totalUsd` 0 and
   * one entry here. Printing that numeral as `US$19,903.44` is what this
   * replaces.
   */
  unpriced: UnpricedAmount[];
  signals: string[];
  score: number;
  level: ExposureLevel;
  sources: string[];
}

export interface ExposureIndex {
  rows: ExposureRow[];
  scannedTables: string[];
  /** Tables where the page budget ran out — every total is a lower bound. */
  truncatedTables: string[];
  /**
   * How much of each table the sweep was actually allowed to read.
   *
   * RLS returns an empty set rather than an error, so before this existed an
   * admin-invisible table and an empty table were the same observation and the
   * console reported one member's holdings as the platform's (F-034).
   */
  coverage: CoverageReport;
  scannedRows: number;
  errors: string[];
  totalMembers: number;
  /** USD exposure across every member, before the display threshold. */
  totalExposureUsd: number;
  /** Unbacked position value across every member, before the threshold. */
  totalUnbackedUsd: number;
  /**
   * Every unconverted holding on the platform, per unit. `totalExposureUsd`
   * covers USD-denominated value only; these sit beside it and are never
   * folded in.
   */
  unpricedTotals: UnpricedAmount[];
  /** The rates the sweep ran with. A null member means that asset was left unpriced. */
  rates: MarketRates;
  minUsd: number;
  ranAt: string;
}

/* ------------------------------------------------------------- the sweep */

interface SweepState {
  scannedTables: string[];
  truncatedTables: string[];
  scannedRows: number;
  errors: string[];
  /**
   * Rows received per table, for the coverage check.
   *
   * `scannedRows` is a total and cannot answer "which table came back short",
   * which is the question F-034 needed asked. A table that threw is
   * deliberately absent rather than recorded as 0: it is already reported in
   * `errors`, and calling it a zero-row read would invite the coverage check
   * to report it a second time as a short read.
   */
  rowsRead: Record<string, number>;
}

/**
 * Read one table and fold it into the accumulator.
 *
 * A table that cannot be read records the error and the sweep continues — a
 * partial exposure figure that says which tables are missing is more useful
 * than no figure at all, provided the UI shows the gap. It does.
 */
async function sweep<T>(
  state: SweepState,
  table: string,
  load: (from: number, to: number) => PromiseLike<PageResponse<T>>,
  apply: (rows: T[]) => void
): Promise<void> {
  try {
    const { rows, truncated } = await paginate(table, load);
    state.scannedTables.push(table);
    state.scannedRows += rows.length;
    state.rowsRead[table] = (state.rowsRead[table] ?? 0) + rows.length;
    if (truncated) state.truncatedTables.push(table);
    apply(rows);
  } catch (error) {
    state.errors.push(error instanceof Error ? error.message : String(error));
  }
}

interface Acc extends ExposureBreakdown {
  /** Quantities with no USD rate, by unit. Never added to any USD field. */
  unpriced: Map<string, number>;
  voucherCount: number;
  uncreditedCount: number;
  pendingTokens: number;
  /** USD credited by an admin: vouchers, approved raises, approved staking. */
  creditedUsd: number;
  signals: Set<string>;
  sources: Set<string>;
}

function blank(): Acc {
  return {
    pendingVouchers: 0, fiat: 0, crypto: 0, staking: 0, shares: 0, vesting: 0,
    safeEquity: 0, subscriptions: 0, nodes: 0, guardian: 0, cards: 0,
    unpriced: new Map<string, number>(),
    voucherCount: 0, uncreditedCount: 0, pendingTokens: 0, creditedUsd: 0,
    signals: new Set<string>(), sources: new Set<string>(),
  };
}

/** A raise or purchase reduced to the fields the exposure rules care about. */
interface SubscriptionEntry {
  userId: string | null;
  usd: number;
  status?: string | null;
  paymentStatus?: string | null;
  creditedAt?: string | null;
  creditedAmount?: number | null;
  sharesCredited?: number | null;
}

interface ProfileRow {
  full_name: string;
  email_address: string;
  str_domain_username: string;
  account_status: string;
  status: string | null;
}

/**
 * Sweep every asset-bearing table and build USD exposure per member.
 *
 * @param minUsd only members at or above this USD exposure are returned —
 *        except those whose unbacked positions alone clear the bar, which are
 *        the accounts that most need looking at.
 */
export async function buildExposureIndex(
  minUsd = MIN_EXPOSURE_USD,
  marketRates?: MarketRates
): Promise<ExposureIndex> {
  // One set of rates for the whole sweep. BTC comes from the same function
  // `/guardian/reserves` reads and ETH from the same `crypto-prices` function
  // the risk radar reads; either being null means that asset is reported as an
  // unconverted quantity rather than valued from a constant. `useExposureIndex`
  // normally supplies them from the shared react-query cache, so the sweep and
  // the scan cannot run on two different prices; the direct fetch here is the
  // fallback for a caller outside React.
  const rates: MarketRates =
    marketRates ?? { btcUsd: await fetchBtcPriceUsd(), ethUsd: await fetchEthPriceUsd() };

  const acc = new Map<string, Acc>();
  const state: SweepState = {
    scannedTables: [], truncatedTables: [], scannedRows: 0, errors: [], rowsRead: {},
  };

  /**
   * USD value of a holding, or null when nothing prices its unit.
   *
   * A null answer records the quantity against its own unit so it can be
   * reported unconverted. The callers add `?? 0` to the USD field, which is
   * honest precisely because the quantity is not lost - it is on the row, in
   * the unit it is actually denominated in.
   */
  const usdOf = (entry: Acc, symbol: string | null | undefined, amount: number): number | null => {
    const value = tokenUsd(symbol, amount, rates);
    if (value !== null) return value;

    if (Number.isFinite(amount) && amount !== 0) {
      const unit = unitLabel(symbol);
      entry.unpriced.set(unit, (entry.unpriced.get(unit) ?? 0) + amount);
    }
    return null;
  };

  const get = (userId: string | null | undefined): Acc | null => {
    if (!userId) return null;
    let entry = acc.get(userId);
    if (!entry) {
      entry = blank();
      acc.set(userId, entry);
    }
    return entry;
  };

  /* ------------------------------- vouchers ------------------------------ */

  // Payment references seen on more than one account. A shared proof means one
  // payment was claimed twice.
  const hashOwners = new Map<string, Set<string>>();

  await sweep(
    state,
    'voucher_redemptions',
    (from, to) =>
      supabase
        .from('voucher_redemptions')
        .select(
          'id, user_id, token_type, package_type, status, amount, tokens_credited, credited_amount, payment_hash, confirmation_number, proof_of_payment_url, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;

        entry.sources.add('voucher_redemptions');
        entry.voucherCount += 1;

        const hash = String(row.payment_hash || row.confirmation_number || '').trim().toLowerCase();
        if (hash.length >= 6) {
          const owners = hashOwners.get(hash) ?? new Set<string>();
          owners.add(row.user_id);
          hashOwners.set(hash, owners);
          if (owners.size > 1) entry.signals.add('Payment proof shared with another account');
        }

        const credited = num(row.credited_amount) || (row.tokens_credited ? num(row.amount) : 0);

        if (row.tokens_credited) {
          // Already credited: the value now lives in wallets and pools, so
          // counting it here too would double it. It IS an admin credit
          // though, and that is what backs staking / shares / vesting.
          entry.creditedUsd +=
            usdFromPackage(row.package_type) || usdOf(entry, row.token_type, credited) || 0;
          if (credited > 0 && num(row.amount) > 0 && credited > num(row.amount) * 1.5) {
            entry.signals.add('Credited above declared voucher value');
          }
          continue;
        }

        if (row.status === 'rejected' || row.status === 'declined') continue;

        entry.uncreditedCount += 1;
        const tokens = voucherTokens(row.package_type, row.token_type);
        entry.pendingTokens += tokens;
        entry.pendingVouchers +=
          usdFromPackage(row.package_type) || usdOf(entry, row.token_type, tokens) || 0;

        if (!row.payment_hash && !row.confirmation_number && !row.proof_of_payment_url) {
          entry.signals.add('Uncredited voucher without payment proof');
        }
      }
    }
  );

  /* --------------------------------- fiat -------------------------------- */

  // Which currencies a member already holds a fiat wallet in, so the IBAN
  // mirroring that wallet is not counted a second time.
  const fiatCurrencies = new Map<string, Set<string>>();

  await sweep(
    state,
    'fiat_wallets',
    (from, to) =>
      supabase
        .from('fiat_wallets')
        .select('id, user_id, currency, balance')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('fiat_wallets');
        // EUR / CHF / GBP have no rate, so this adds nothing and the balance is
        // recorded unconverted instead. It used to add the numeral as dollars.
        entry.fiat += usdOf(entry, row.currency, num(row.balance)) ?? 0;

        const currencies = fiatCurrencies.get(row.user_id) ?? new Set<string>();
        currencies.add(String(row.currency ?? 'USD').toUpperCase());
        fiatCurrencies.set(row.user_id, currencies);

        if (num(row.balance) < 0) entry.signals.add('Negative fiat balance');
      }
    }
  );

  await sweep(
    state,
    'iban_accounts',
    (from, to) =>
      supabase
        .from('iban_accounts')
        .select('id, user_id, currency, balance, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        // An IBAN account mirrors the fiat wallet of the same currency. Adding
        // both doubles the member's cash — on the seeded data that alone would
        // have reported twice the real fiat exposure.
        const currency = String(row.currency ?? 'USD').toUpperCase();
        if (fiatCurrencies.get(row.user_id)?.has(currency)) continue;
        entry.sources.add('iban_accounts');
        entry.fiat += usdOf(entry, row.currency, num(row.balance)) ?? 0;
      }
    }
  );

  /* -------------------------------- crypto ------------------------------- */

  await sweep(
    state,
    'crypto_wallets',
    (from, to) =>
      supabase
        .from('crypto_wallets')
        .select('id, user_id, token_type, balance')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('crypto_wallets');
        entry.crypto += usdOf(entry, row.token_type, num(row.balance)) ?? 0;
        if (num(row.balance) < 0) entry.signals.add('Negative crypto balance');
      }
    }
  );

  await sweep(
    state,
    'user_wallets',
    (from, to) =>
      supabase
        .from('user_wallets')
        .select('id, user_id, arss_balance')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('user_wallets');
        entry.crypto += usdOf(entry, 'ARSS', num(row.arss_balance)) ?? 0;
      }
    }
  );

  /* -------------------------- staking / shares --------------------------- */

  await sweep(
    state,
    'user_staking_pools',
    (from, to) =>
      supabase
        .from('user_staking_pools')
        .select('id, user_id, pool_type, balance, staked_amount, rewards_earned, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('user_staking_pools');

        // F-032: `balance` is the live holding and `staked_amount` is the
        // principal AS FIRST CREDITED — two records of the SAME tokens, not two
        // holdings. Measured on production: credit_voucher_tokens writes the
        // same quantity into both, calculate_daily_rewards then adds each reward
        // into `balance` and `rewards_earned` and never into `staked_amount`,
        // get_available_balance is SUM(balance), and 54,499 of 56,836 rows have
        // the two columns equal. So `balance` is exposure, and `rewards_earned`
        // is ALREADY INSIDE it — adding it again double-counted every accrued
        // reward.
        //
        // The old `balance || staked_amount` was the fallback pattern
        // lib/balances.ts exists to forbid, inverted: a pool sold down to zero
        // reported its full original principal as live exposure, because 0 is
        // falsy. `staked_amount` is now used only when `balance` is NULL, which
        // means "never written" rather than "spent to nothing".
        const held = row.balance === null ? num(row.staked_amount) : num(row.balance);
        // `domain` and `estr` pools have no rate. tokenUsd's old fallback priced
        // them at the STR rate; they now land in `unpriced` under their own name.
        entry.staking += usdOf(entry, row.pool_type, held) ?? 0;

        if (num(row.balance) < 0) entry.signals.add('Negative staking pool');
        if (num(row.rewards_earned) > num(row.staked_amount) * 2 && num(row.rewards_earned) > 1000) {
          entry.signals.add('Staking rewards exceed principal');
        }
      }
    }
  );

  /*
   * Tokens locked against a marketplace listing.
   *
   * These have LEFT `user_staking_pools.balance` — that is what the escrow lock
   * does — so without this read they are exposure the platform carries and the
   * console cannot see. The gap predates the F-032 rewrite (the old
   * `debit_staking_pool_balance` removed them from `balance` too, and nothing
   * counted them anywhere), but making escrow a real ledger bucket is what made
   * it worth closing rather than merely noting.
   *
   * Only `locked` rows count. A `released` row's tokens are back in `balance`
   * and would otherwise be counted twice; a `transferred` row's tokens belong
   * to the buyer.
   */
  await sweep(
    state,
    'marketplace_escrow_balances',
    (from, to) =>
      supabase
        .from('marketplace_escrow_balances')
        .select('id, user_id, asset_symbol, amount, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        // Filtered HERE, not in the query. A server-side `.eq('status',
        // 'locked')` would make the row count the sweep reports smaller than
        // the table's, and the coverage check would read that as an
        // RLS-shortened read (F-034). Every sweep in this file reads its table
        // whole and narrows in the fold; that is what makes the comparison
        // against admin_sweep_row_counts mean anything.
        if (row.status !== 'locked') continue;
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('marketplace_escrow_balances');
        entry.staking += usdOf(entry, row.asset_symbol, num(row.amount)) ?? 0;
      }
    }
  );

  await sweep(
    state,
    'user_str_shares',
    (from, to) =>
      supabase
        .from('user_str_shares')
        .select('id, user_id, balance, locked_balance, wnft_shares')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('user_str_shares');
        entry.shares += usdOf(entry, 'STR', num(row.balance) + num(row.locked_balance)) ?? 0;
        if (num(row.locked_balance) > num(row.balance) + 0.01) {
          entry.signals.add('Locked shares exceed balance');
        }
      }
    }
  );

  await sweep(
    state,
    'vesting_tokens',
    (from, to) =>
      supabase
        .from('vesting_tokens')
        .select('id, user_id, token_type, amount, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        if (String(row.status ?? '').toLowerCase() === 'cancelled') continue;
        entry.sources.add('vesting_tokens');
        entry.vesting += usdOf(entry, row.token_type, num(row.amount)) ?? 0;
      }
    }
  );

  /* -------------------------------- equity ------------------------------- */

  await sweep(
    state,
    'safe_purchases',
    (from, to) =>
      supabase
        .from('safe_purchases')
        .select('id, user_id, total_usd, total_shares, credited_shares, status, credited_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        if (isDead({ status: row.status })) continue;
        entry.sources.add('safe_purchases');
        entry.safeEquity += num(row.total_usd);
        if (row.credited_at && num(row.credited_shares) !== num(row.total_shares)) {
          entry.signals.add('SAFE credited shares mismatch');
        }
      }
    }
  );

  /* ---------------------- subscriptions / raises ------------------------- */

  /**
   * Units and double counting, both of which v2 got wrong at least once:
   *
   *  - seed applications store `investment_amount` in $STR TOKENS
   *    (`investment_currency = 'STR'`), not in USD. Reading it as USD inflated
   *    exposure by orders of magnitude, so it is valued through `tokenUsd`.
   *  - once a subscription is credited, the tokens or shares already appear in
   *    staking pools, shares or vesting. Counting the subscription again counts
   *    the same asset twice, so only uncredited subscriptions add exposure —
   *    credited ones become admin credit instead.
   */
  const applySubscriptions = (source: string, entries: SubscriptionEntry[]): void => {
    for (const item of entries) {
      const entry = get(item.userId);
      if (!entry) continue;
      if (isDead(item)) continue;
      if (isCredited(item)) {
        entry.creditedUsd += item.usd;
        continue;
      }
      entry.sources.add(source);
      entry.subscriptions += item.usd;
    }
  };

  const SEED_COLUMNS =
    'id, user_id, investment_amount, credited_amount, payment_amount, str_shares_credited, credited_at, status, payment_status';

  await sweep(
    state,
    'seed_str_applications',
    (from, to) =>
      supabase
        .from('seed_str_applications')
        .select(SEED_COLUMNS)
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'seed_str_applications',
        rows.map((row) => ({
          userId: row.user_id,
          // STR is priced from a constant, so this is never null; the `?? 0`
          // satisfies the type without papering over a missing rate.
          usd: num(row.payment_amount) || (tokenUsd('STR', num(row.investment_amount)) ?? 0),
          status: row.status,
          paymentStatus: row.payment_status,
          creditedAt: row.credited_at,
          creditedAmount: row.credited_amount,
          sharesCredited: row.str_shares_credited,
        }))
      )
  );

  await sweep(
    state,
    'private_seed_str_applications',
    (from, to) =>
      supabase
        .from('private_seed_str_applications')
        .select(SEED_COLUMNS)
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'private_seed_str_applications',
        rows.map((row) => ({
          userId: row.user_id,
          // STR is priced from a constant, so this is never null; the `?? 0`
          // satisfies the type without papering over a missing rate.
          usd: num(row.payment_amount) || (tokenUsd('STR', num(row.investment_amount)) ?? 0),
          status: row.status,
          paymentStatus: row.payment_status,
          creditedAt: row.credited_at,
          creditedAmount: row.credited_amount,
          sharesCredited: row.str_shares_credited,
        }))
      )
  );

  await sweep(
    state,
    'private_str_ipo_purchases',
    (from, to) =>
      supabase
        .from('private_str_ipo_purchases')
        .select('id, user_id, usd_amount, payment_status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'private_str_ipo_purchases',
        rows.map((row) => ({
          userId: row.user_id,
          usd: num(row.usd_amount),
          paymentStatus: row.payment_status,
        }))
      )
  );

  await sweep(
    state,
    'private_str_prelisting_purchases',
    (from, to) =>
      supabase
        .from('private_str_prelisting_purchases')
        .select('id, user_id, usd_amount, payment_status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'private_str_prelisting_purchases',
        rows.map((row) => ({
          userId: row.user_id,
          usd: num(row.usd_amount),
          paymentStatus: row.payment_status,
        }))
      )
  );

  await sweep(
    state,
    'private_digital_shares_purchases',
    (from, to) =>
      supabase
        .from('private_digital_shares_purchases')
        .select('id, user_id, total_usd, payment_status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'private_digital_shares_purchases',
        rows.map((row) => ({
          userId: row.user_id,
          usd: num(row.total_usd),
          paymentStatus: row.payment_status,
        }))
      )
  );

  await sweep(
    state,
    'arss_token_purchases',
    (from, to) =>
      supabase
        .from('arss_token_purchases')
        .select('id, user_id, usd_amount, credited_at, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'arss_token_purchases',
        rows.map((row) => ({
          userId: row.user_id,
          usd: num(row.usd_amount),
          status: row.status,
          creditedAt: row.credited_at,
        }))
      )
  );

  await sweep(
    state,
    'ccos_purchases',
    (from, to) =>
      supabase
        .from('ccos_purchases')
        .select('id, user_id, package_amount_usd, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) =>
      applySubscriptions(
        'ccos_purchases',
        rows.map((row) => ({
          userId: row.user_id,
          usd: num(row.package_amount_usd),
          status: row.status,
        }))
      )
  );

  /* -------------- admin-approved staking requests (credit truth) --------- */

  await sweep(
    state,
    'staking_requests',
    (from, to) =>
      supabase
        .from('staking_requests')
        .select('id, user_id, pool_type, amount, status, approved_by')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        const status = String(row.status ?? '').toLowerCase();
        if (!['approved', 'completed', 'credited', 'processed'].includes(status)) continue;
        // Must be an explicit admin decision, not a status the member set.
        if (!row.approved_by) continue;
        entry.creditedUsd += usdOf(entry, row.pool_type, num(row.amount)) ?? 0;
      }
    }
  );

  /* --------------------------------- nodes ------------------------------- */

  await sweep(
    state,
    'starw_purchases',
    (from, to) =>
      supabase
        .from('starw_purchases')
        .select('id, user_id, total_cost, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        if (isDead({ status: row.status })) continue;
        entry.sources.add('starw_purchases');
        entry.nodes += num(row.total_cost);
      }
    }
  );

  await sweep(
    state,
    'supernode_purchases',
    (from, to) =>
      supabase
        .from('supernode_purchases')
        .select('id, user_id, total_cost, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        if (isDead({ status: row.status })) continue;
        entry.sources.add('supernode_purchases');
        entry.nodes += num(row.total_cost);
      }
    }
  );

  /* ---------------------------- vaults & cards --------------------------- */

  await sweep(
    state,
    'guardian_wallets',
    (from, to) =>
      supabase
        .from('guardian_wallets')
        .select('id, user_id, asset_symbol, balance, external_balance, usd_value')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('guardian_wallets');
        entry.guardian +=
          num(row.usd_value) ||
          usdOf(entry, row.asset_symbol, num(row.balance) + num(row.external_balance)) ||
          0;
      }
    }
  );

  await sweep(
    state,
    'prepaid_cards',
    (from, to) =>
      supabase
        .from('prepaid_cards')
        .select('id, user_id, currency, balance, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        entry.sources.add('prepaid_cards');
        entry.cards += usdOf(entry, row.currency, num(row.balance)) ?? 0;
        if (num(row.balance) < 0) entry.signals.add('Negative card balance');
      }
    }
  );

  /* -------------------------- withdrawal pressure ------------------------ */

  await sweep(
    state,
    'withdrawal_requests',
    (from, to) =>
      supabase
        .from('withdrawal_requests')
        .select('id, user_id, usd_value_at_request, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const entry = get(row.user_id);
        if (!entry) continue;
        const value = num(row.usd_value_at_request);
        if (String(row.status ?? '').toLowerCase() === 'pending' && value >= 10_000) {
          entry.signals.add(`Pending withdrawal $${Math.round(value).toLocaleString()}`);
        }
      }
    }
  );

  /* ------------------------------- profiles ------------------------------ */

  const profiles = new Map<string, ProfileRow>();

  await sweep(
    state,
    'user_profiles',
    (from, to) =>
      supabase
        .from('user_profiles')
        .select('id, user_id, full_name, email_address, str_domain_username, account_status, status')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        profiles.set(row.user_id, {
          full_name: row.full_name,
          email_address: row.email_address,
          str_domain_username: row.str_domain_username,
          account_status: row.account_status,
          status: row.status,
        });
      }
    }
  );

  /* -------------------------------- assemble ----------------------------- */

  const rows: ExposureRow[] = [];
  let totalExposureUsd = 0;
  let totalUnbackedUsd = 0;
  const unpricedTotal = new Map<string, number>();

  acc.forEach((entry, userId) => {
    /**
     * SINGLE SOURCE OF TRUTH for staking / shares / vesting: the admin credit.
     *
     * Table balances are claims, not facts. Anything above what an admin
     * actually credited — through a credited voucher, a credited raise or an
     * admin-approved staking request — is unbacked: it is excluded from
     * exposure, reported separately, and flagged.
     */
    const positionsUsd = round2(entry.staking + entry.shares + entry.vesting);
    const adminCreditedUsd = round2(entry.creditedUsd);
    const backedRatio = positionsUsd <= 0 ? 1 : Math.min(1, adminCreditedUsd / positionsUsd);
    const unbackedUsd = round2(Math.max(0, positionsUsd - adminCreditedUsd));

    entry.staking = round2(entry.staking * backedRatio);
    entry.shares = round2(entry.shares * backedRatio);
    entry.vesting = round2(entry.vesting * backedRatio);

    if (unbackedUsd >= 10_000) {
      entry.signals.add(
        adminCreditedUsd <= 0
          ? `Staking/shares/vesting with NO admin credit ($${Math.round(unbackedUsd).toLocaleString()})`
          : `Positions exceed admin credit by $${Math.round(unbackedUsd).toLocaleString()}`
      );
    }

    const breakdown: ExposureBreakdown = {
      pendingVouchers: round2(entry.pendingVouchers),
      fiat: round2(entry.fiat),
      crypto: round2(entry.crypto),
      staking: entry.staking,
      shares: entry.shares,
      vesting: entry.vesting,
      safeEquity: round2(entry.safeEquity),
      subscriptions: round2(entry.subscriptions),
      nodes: round2(entry.nodes),
      guardian: round2(entry.guardian),
      cards: round2(entry.cards),
    };

    const totalUsd = round2(BREAKDOWN_KEYS.reduce((sum, key) => sum + breakdown[key], 0));
    totalExposureUsd += totalUsd;
    totalUnbackedUsd += unbackedUsd;

    const unpriced: UnpricedAmount[] = [...entry.unpriced]
      .filter(([, amount]) => amount !== 0)
      .map(([unit, amount]) => ({ unit, amount: round2(amount) }))
      .sort((a, b) => b.amount - a.amount);

    for (const item of unpriced) {
      unpricedTotal.set(item.unit, (unpricedTotal.get(item.unit) ?? 0) + item.amount);
    }

    // Keep accounts whose unbacked positions alone are material even when the
    // backed exposure falls under the threshold — those are the real risk.
    // A holding nobody can price is also worth seeing, so an account carrying
    // one is kept regardless of its USD figure: excluding it would make the
    // unpriceable invisible, which is the failure this whole change is about.
    if (totalUsd < minUsd && unbackedUsd < minUsd && unpriced.length === 0) return;

    const profile = profiles.get(userId);

    // Both status columns are meant to be kept in sync, but never trust one
    // alone: the strictest non-approved value wins, so a quarantine cannot be
    // rendered as "approved" because of a stale mirror column.
    const statuses = [profile?.status, profile?.account_status]
      .map((value) => String(value ?? '').toLowerCase().trim())
      .filter(Boolean);
    const accountStatus =
      statuses.find((s) => s !== 'approved' && s !== 'active') ?? statuses[0] ?? 'unknown';

    const signals = [...entry.signals];

    let score = 0;
    if (totalUsd >= 1_000_000) score += 55;
    else if (totalUsd >= 250_000) score += 40;
    else if (totalUsd >= 100_000) score += 30;
    else if (totalUsd >= 25_000) score += 18;
    else score += 10;

    if (breakdown.pendingVouchers >= 100_000) score += 25;
    else if (breakdown.pendingVouchers >= 25_000) score += 15;
    else if (breakdown.pendingVouchers >= 10_000) score += 8;

    if (entry.voucherCount >= 5) {
      score += 10;
      signals.push(`${entry.voucherCount} voucher submissions`);
    }
    if (signals.some((s) => s.startsWith('Payment proof shared'))) score += 30;
    if (signals.some((s) => s.startsWith('Uncredited voucher without'))) score += 20;
    if (signals.some((s) => s.startsWith('Negative'))) score += 25;
    if (signals.some((s) => s.startsWith('Staking/shares/vesting with NO admin credit'))) score += 35;
    else if (signals.some((s) => s.startsWith('Positions exceed admin credit'))) score += 20;
    if (accountStatus !== 'approved') {
      score += 12;
      signals.push(`Account status: ${accountStatus}`);
    }
    if (entry.sources.size >= 6) signals.push(`Assets across ${entry.sources.size} systems`);
    if (unpriced.length > 0) {
      signals.push(
        `Unpriced: ${unpriced.map((u) => `${u.amount.toLocaleString()} ${u.unit}`).join(', ')}`
      );
    }

    score = Math.min(score, 100);
    const level: ExposureLevel =
      score >= 70 ? 'critical' : score >= 50 ? 'high' : score >= 30 ? 'medium' : 'low';

    rows.push({
      userId,
      name: profile?.full_name || '—',
      email: profile?.email_address || '—',
      domain: profile?.str_domain_username || '—',
      accountStatus,
      totalUsd,
      breakdown,
      voucherCount: entry.voucherCount,
      uncreditedCount: entry.uncreditedCount,
      pendingTokens: entry.pendingTokens,
      adminCreditedUsd,
      positionsUsd,
      unbackedUsd,
      unpriced,
      signals: signals.length ? signals : ['Large balance — no anomaly signals'],
      score,
      level,
      sources: [...entry.sources],
    });
  });

  rows.sort((a, b) => b.totalUsd - a.totalUsd);

  // Asked once, after every table has been read, and never allowed to throw:
  // a failed coverage check must not take down the exposure figure it
  // annotates. It downgrades to `verified: false`, which the UI states.
  const coverage = await checkCoverage(state.rowsRead);

  return {
    rows,
    coverage,
    scannedTables: state.scannedTables,
    truncatedTables: state.truncatedTables,
    scannedRows: state.scannedRows,
    errors: state.errors,
    totalMembers: acc.size,
    totalExposureUsd: round2(totalExposureUsd),
    totalUnbackedUsd: round2(totalUnbackedUsd),
    unpricedTotals: [...unpricedTotal]
      .filter(([, amount]) => amount !== 0)
      .map(([unit, amount]) => ({ unit, amount: round2(amount) }))
      .sort((a, b) => b.amount - a.amount),
    rates,
    minUsd,
    ranAt: new Date().toISOString(),
  };
}

/** Total USD per asset class across a set of rows, for the composition chart. */
export function compositionOf(rows: ExposureRow[]): { label: string; value: number }[] {
  const totals = BREAKDOWN_KEYS.map((key) => ({
    label: BREAKDOWN_LABELS[key],
    value: round2(rows.reduce((sum, row) => sum + row.breakdown[key], 0)),
  }));
  return totals.filter((entry) => entry.value > 0).sort((a, b) => b.value - a.value);
}

export function levelCounts(rows: ExposureRow[]): Record<ExposureLevel, number> {
  const counts: Record<ExposureLevel, number> = { critical: 0, high: 0, medium: 0, low: 0 };
  for (const row of rows) counts[row.level] += 1;
  return counts;
}

export function exposureToCsv(rows: ExposureRow[]): string {
  const head = [
    'user_id', 'name', 'email', 'str_domain', 'account_status', 'risk_level', 'risk_score',
    'total_exposure_usd', 'pending_vouchers_usd', 'fiat_usd', 'crypto_usd', 'staking_usd',
    'shares_usd', 'vesting_usd', 'safe_equity_usd', 'subscriptions_usd', 'nodes_usd',
    'guardian_usd', 'cards_usd', 'admin_credited_usd', 'positions_usd', 'unbacked_usd',
    // Quantities with no USD rate, e.g. "19903.44 CHF | 81304 DOMAIN". Kept out
    // of every _usd column above rather than converted at a rate nobody has.
    'unpriced_unconverted',
    'voucher_count', 'uncredited_vouchers', 'signals', 'sources',
  ];
  const escape = (value: unknown) => `"${String(value ?? '').replace(/"/g, '""')}"`;

  return [
    head.join(','),
    ...rows.map((row) =>
      [
        row.userId, row.name, row.email, row.domain, row.accountStatus, row.level, row.score,
        row.totalUsd.toFixed(2), row.breakdown.pendingVouchers.toFixed(2),
        row.breakdown.fiat.toFixed(2), row.breakdown.crypto.toFixed(2),
        row.breakdown.staking.toFixed(2), row.breakdown.shares.toFixed(2),
        row.breakdown.vesting.toFixed(2), row.breakdown.safeEquity.toFixed(2),
        row.breakdown.subscriptions.toFixed(2), row.breakdown.nodes.toFixed(2),
        row.breakdown.guardian.toFixed(2), row.breakdown.cards.toFixed(2),
        row.adminCreditedUsd.toFixed(2), row.positionsUsd.toFixed(2), row.unbackedUsd.toFixed(2),
        row.unpriced.map((u) => `${u.amount} ${u.unit}`).join(' | '),
        row.voucherCount, row.uncreditedCount,
        row.signals.join(' | '), row.sources.join(' '),
      ]
        .map(escape)
        .join(',')
    ),
  ].join('\n');
}
