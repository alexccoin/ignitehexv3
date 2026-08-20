/**
 * Turning stored balances into one comparable USD figure.
 *
 * Ported from v2's `src/lib/platformExposure.ts` (the `num` / `tokenUsd` half),
 * `src/lib/packageOptions.ts` and `src/lib/hardenedStr.ts`, with one deliberate
 * behavioural change recorded below.
 *
 * THE CHANGE: v2 priced STR through `getHardenedSTRPrice()`, which returns
 * `0.028 + Math.random() * 0.0038`. Every re-scan therefore produced a different
 * platform exposure — up to a 13.6% swing on the same unchanged data — and two
 * administrators looking at the same accounts at the same moment saw different
 * numbers. A risk figure that moves when you press refresh cannot be acted on,
 * so STR is priced here at the documented active redemption rate. All rates are
 * constants and the sweep is reproducible.
 */

/** $10.13 per CCOS (v2 packageOptions.ts:67). */
export const CCOS_USD = 10.13;
/** $0.00911 per ARSS (v2 packageOptions.ts:71). */
export const ARSS_USD = 0.00911;
/** $0.005 per STR — the active vesting redemption rate (v2 packageOptions.ts:69). */
export const STR_USD = 0.005;
/** wSTR trades at a premium to STR (v2 platformExposure.ts). */
export const WSTR_PREMIUM = 1.13;

/**
 * Rates that are not constants.
 *
 * BTC used to be `const BTC_USD = 118_000` here while `/guardian/reserves`
 * annotated the same asset from the `btc-price` edge function, which returned
 * 64,260 — the two pages of one app disagreed by 1.84x about what a bitcoin is
 * worth. There is now one source, `lib/btcPrice.ts`, and both pages read it.
 *
 * ETH was the same defect, one line further down and undetected for longer:
 * `const ETH_USD = 3_600`. No second page ever priced ETH, so there was no
 * disagreement to notice — the number was simply wrong, by 1.86x against the
 * feed on the day it was removed. It now comes from `lib/ethPrice.ts`, which
 * reads the `crypto-prices` function, the only ETH source in this system.
 *
 * A failed lookup is `null`, never a fallback constant and never 0: a balance
 * whose price could not be fetched is reported as an unconverted quantity. A 0
 * would be worse than a stale constant, because a zero dollar value is
 * indistinguishable from an account that genuinely holds none of the asset.
 */
export interface MarketRates {
  /** USD per BTC as reported by the `btc-price` function, or null if it failed. */
  btcUsd: number | null;
  /** USD per ETH as reported by the `crypto-prices` function, or null if it failed. */
  ethUsd: number | null;
}

/** No live rate available. Anything priced from a feed comes back unpriced. */
export const NO_RATES: MarketRates = { btcUsd: null, ethUsd: null };

/**
 * Units that are genuinely one US dollar.
 *
 * EUR, CHF and GBP used to be in this set. They are not dollars: at the rates
 * of the day GBP was understated by roughly 27% and EUR by roughly 8%, and
 * `moderator CHF 19,903.44` printed on the risk console as `US$19,903.44`.
 * There is no FX source in this system, so those currencies have no USD value
 * here and are reported unconverted instead. Inventing a rate would be worse
 * than saying so.
 */
const PAR_USD = new Set(['USD', 'USDT', 'USDC']);

/** Spellings that mean an existing symbol. `STR_STABLE` normalises to `STRSTABLE`. */
const ALIASES: Record<string, string> = { STRSTABLE: 'STR' };

/**
 * Robust numeric parser.
 *
 * Money columns in this database are a mix of `numeric` (which supabase-js
 * hands back as a number), `text` (Postgres numeric strings) and — in
 * `voucher_redemptions.amount` — human-entered values carrying thousand
 * separators and currency symbols in both US ("1,234.56") and EU ("1.234,56")
 * notation. `Number()` returns NaN for most of those, and NaN spreads through
 * every total it touches.
 */
export function num(value: unknown): number {
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (value === null || value === undefined) return 0;

  let s = String(value).trim().replace(/[^0-9.,-]/g, '');
  if (!s) return 0;

  const lastComma = s.lastIndexOf(',');
  const lastDot = s.lastIndexOf('.');

  if (lastComma > -1 && lastDot > -1) {
    // The right-most separator is the decimal separator.
    s = lastComma > lastDot ? s.replace(/\./g, '').replace(',', '.') : s.replace(/,/g, '');
  } else if (lastComma > -1) {
    // "1,234" is thousands; "1,23" is a decimal.
    s = s.length - lastComma - 1 === 3 ? s.replace(/,/g, '') : s.replace(',', '.');
  }

  const n = parseFloat(s);
  return Number.isFinite(n) ? n : 0;
}

export const round2 = (n: number): number =>
  Math.round((Number.isFinite(n) ? n : 0) * 100) / 100;

/**
 * USD value of an amount of a token, pool type or currency — or null.
 *
 * NULL MEANS "NO RATE", AND THE CALLER MUST RENDER IT AS UNPRICED.
 *
 * This function used to end `return amount * STR_USD`, so every symbol nobody
 * had priced silently acquired the STR rate: `domain` and `estr` pools, and any
 * token added to an asset table afterwards, appeared in the exposure figures at
 * a price no one chose. The old `s.includes('STR')` test made that worse by
 * catching `STR_STABLE` and anything else with those three letters in it.
 * Matching is now exact, through an explicit alias table, and an unknown symbol
 * returns null so it shows up as unvalued rather than as a number.
 *
 * Returning 0 instead would be just as wrong in the other direction — it hides
 * the holding. Null is the only answer that says what is true: this quantity
 * exists and we cannot state its dollar value.
 */
export function tokenUsd(
  symbol: string | null | undefined,
  amount: number,
  rates: MarketRates = NO_RATES
): number | null {
  if (!amount || !Number.isFinite(amount)) return 0;

  const raw = String(symbol ?? '').toUpperCase().replace(/[^A-Z]/g, '');
  const s = ALIASES[raw] ?? raw;

  if (s === 'CCOS') return amount * CCOS_USD;
  if (s === 'ARSS') return amount * ARSS_USD;
  if (s === 'WSTR') return amount * STR_USD * WSTR_PREMIUM;
  if (s === 'STR') return amount * STR_USD;
  if (s === 'ETH') return rates.ethUsd === null ? null : amount * rates.ethUsd;
  if (s === 'BTC') return rates.btcUsd === null ? null : amount * rates.btcUsd;
  if (PAR_USD.has(s)) return amount;

  return null;
}

/** The symbol as it should be printed beside an unconverted quantity. */
export function unitLabel(symbol: string | null | undefined): string {
  const raw = String(symbol ?? '').toUpperCase().replace(/[^A-Z0-9_]/g, '');
  return raw || 'UNKNOWN';
}

/** The USD figure printed on a voucher package label, e.g. "Core ($500) ≈ …". */
export function usdFromPackage(packageType: string | null | undefined): number {
  if (!packageType) return 0;
  const match = packageType.match(/\$\s?([0-9][0-9.,]*)/);
  return match ? num(match[1]) : 0;
}

/**
 * Pre-CEX STR vouchers (May 2026). Token amounts are FIXED by the programme,
 * not derived from price-per-token arithmetic, so they need an exact table.
 * Ported from v2 packageOptions.ts:105-119.
 */
const PRECEX_STR_TOKENS: Record<number, number> = {
  250: 166_666,
  500: 333_333,
  750: 500_000,
  1_000: 666_666,
  1_250: 833_333,
  1_500: 1_000_000,
  2_000: 1_333_333,
  2_500: 1_666_666,
  5_000: 3_333_333,
  10_000: 6_666_666,
  25_000: 16_666_666,
  50_000: 33_333_333,
  100_000: 66_666_666,
};

/**
 * How many tokens a voucher package is worth.
 *
 * v2's `getTokenAmountForVoucher` consulted a 90-entry map of historical label
 * spellings — the same package written six ways as the price rate changed over
 * three years. Rather than carry that table, the label's USD figure is parsed
 * and divided by the token's rate, which reproduces every generated entry in
 * that map exactly. Only the Pre-CEX STR tier needs the lookup, because its
 * token amounts were never derived from a rate at all.
 */
export function voucherTokens(
  packageType: string | null | undefined,
  tokenType: string | null | undefined
): number {
  const usd = usdFromPackage(packageType);
  if (usd <= 0) return 0;

  const raw = String(tokenType ?? '').trim().toUpperCase();
  const token = raw === 'STR_STABLE' ? 'STR' : raw;

  if (token === 'STR') {
    const fixed = PRECEX_STR_TOKENS[usd];
    if (fixed !== undefined) return fixed;
    return round2(usd / STR_USD);
  }
  if (token === 'CCOS') return round2(usd / CCOS_USD);
  if (token === 'ARSS') return round2(usd / ARSS_USD);

  return 0;
}

/**
 * States that carry no exposure.
 *
 * Checked on BOTH `status` and `payment_status`: a row can read
 * `status = 'suspended'` while `payment_status = 'cancelled'`, and such a row
 * must never add to anybody's exposure.
 */
const DEAD_STATES = new Set([
  'rejected', 'declined', 'cancelled', 'canceled', 'expired', 'failed',
  'suspended', 'void', 'voided', 'refunded', 'deleted', 'archived', 'closed', 'withdrawn',
]);

export interface StatusPair {
  status?: string | null;
  paymentStatus?: string | null;
}

export function isDead(row: StatusPair): boolean {
  const status = String(row.status ?? '').toLowerCase().trim();
  const payment = String(row.paymentStatus ?? '').toLowerCase().trim();
  return DEAD_STATES.has(status) || DEAD_STATES.has(payment);
}

export interface CreditMarkers extends StatusPair {
  creditedAt?: string | null;
  creditedAmount?: number | null;
  sharesCredited?: number | null;
}

/**
 * Whether a subscription has already been credited into wallets, pools or
 * shares — in which case counting the subscription again double-counts the
 * same asset.
 */
export function isCredited(row: CreditMarkers): boolean {
  if (row.creditedAt) return true;
  if (num(row.creditedAmount) > 0) return true;
  if (num(row.sharesCredited) > 0) return true;

  const status = String(row.status ?? '').toLowerCase();
  const payment = String(row.paymentStatus ?? '').toLowerCase();
  return (
    status === 'credited' || status === 'completed' || status === 'distributed' ||
    payment === 'credited' || payment === 'completed'
  );
}
