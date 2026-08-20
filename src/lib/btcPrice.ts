import { supabase } from './supabase';

/**
 * The one place the app learns what a bitcoin is worth.
 *
 * There used to be two. `/guardian/reserves` invoked the `btc-price` edge
 * function and rendered "≈ US$394,465,292.31 at US$64,244.00/BTC"; the risk
 * console valued the same asset from `const BTC_USD = 118_000` in
 * `domains/admin/lib/valuation.ts`. Two pages of one application disagreed by
 * 1.84x about the price of the largest asset on the balance sheet, and nothing
 * on either page said which one to believe.
 *
 * Everything that needs a BTC price now calls this. There is no constant to
 * drift away from it.
 *
 * A FAILURE IS NULL, NOT A FALLBACK. If the feed cannot be reached the figure
 * is omitted — `/guardian/reserves` prints the BTC quantity with no conversion,
 * and the risk console reports the holding as unpriced. A hardcoded default
 * would put a number on screen that no source stands behind, which is the
 * failure this file exists to prevent.
 */

/** Shared react-query key, so one fetch serves every consumer. */
export const btcPriceKey = ['btc-price'] as const;

/** USD per BTC, or null when the price could not be established. */
export async function fetchBtcPriceUsd(): Promise<number | null> {
  const { data, error } = await supabase.functions.invoke<{ price?: number }>('btc-price');
  if (error) return null;

  const price = data?.price;
  return typeof price === 'number' && Number.isFinite(price) && price > 0 ? price : null;
}
