import { supabase } from './supabase';

/**
 * The one place the app learns what an ether is worth.
 *
 * The twin of `btcPrice.ts`, written for the same reason and to the same
 * rules. `domains/admin/lib/valuation.ts` carried `const ETH_USD = 3_600`
 * beside the `BTC_USD = 118_000` that F-017 removed. Nothing ever contradicted
 * the ETH constant on screen, so it survived the BTC fix — and it was wrong by
 * more than the BTC one had been: on the day this was written the feed
 * reported 1,932.25, so every ETH holding in the risk console was valued at
 * 1.86x what the market said.
 *
 * The feed is the `crypto-prices` edge function, which reads ETH from
 * CoinGecko. It is the only source of an ETH price anywhere in this system.
 *
 * A FAILURE IS NULL, NOT A FALLBACK. If the feed cannot be reached, or answers
 * without a usable ETH price, the conversion is omitted: the risk console
 * reports the holding as an unconverted ETH quantity, exactly as it does for
 * BTC when `btc-price` is down. It is never zero either — a zero would be
 * indistinguishable from an account that really holds no ether, which is a
 * different and much less alarming fact.
 */

/** Shared react-query key, so one fetch serves every consumer. */
export const ethPriceKey = ['eth-price'] as const;

/**
 * What `crypto-prices` returns. `fallback: true` marks the response the
 * function emits when every upstream API failed: a table of prices *derived*
 * from a randomised STR figure, carrying no ETH entry at all. It is treated as
 * a failure here rather than parsed, because a derived price is not a price.
 */
interface CryptoPricesResponse {
  success?: boolean;
  fallback?: boolean;
  data?: Record<string, { price?: number } | undefined>;
}

/** USD per ETH, or null when the price could not be established. */
export async function fetchEthPriceUsd(): Promise<number | null> {
  const { data, error } = await supabase.functions.invoke<CryptoPricesResponse>('crypto-prices', {
    body: { symbols: 'ETH' },
  });
  if (error) return null;
  if (data?.fallback) return null;

  const price = data?.data?.ETH?.price;
  return typeof price === 'number' && Number.isFinite(price) && price > 0 ? price : null;
}
