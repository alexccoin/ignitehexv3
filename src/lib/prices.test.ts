import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Price feeds.
 *
 * One rule, tested from every angle it has been broken from: a price that could
 * not be established is null. Never a constant, never 0.
 *
 *  - A CONSTANT was the shipped defect twice. `valuation.ts` carried
 *    `BTC_USD = 118_000` while the reserves page invoked the feed and got
 *    64,244 — two pages of one app disagreeing by 1.84x about the largest asset
 *    on the balance sheet (F-017). The ETH twin, `ETH_USD = 3_600`, survived
 *    that fix and was worse: the feed said 1,932.25 the day it was measured, so
 *    every ETH holding was valued at 1.86x the market, overstating one holding
 *    by US$20,805 (F-035).
 *  - A ZERO is not a safer fallback. "This holding is worth nothing" is a
 *    perfectly readable, entirely wrong statement; "we could not price this" is
 *    the true one.
 *
 * Both tests below assert the failure path explicitly rather than only the
 * happy path, because it is the failure path that has actually shipped wrong.
 */

const invoke = vi.fn();
vi.mock('@/lib/supabase', () => ({
  supabase: { functions: { invoke: (...args: unknown[]) => invoke(...args) } },
  isLocal: true,
}));

import { fetchBtcPriceUsd, btcPriceKey } from './btcPrice';
import { fetchEthPriceUsd, ethPriceKey } from './ethPrice';

/** The constants that were removed. Nothing may ever return one of these. */
const REMOVED_CONSTANTS = { BTC_USD: 118_000, ETH_USD: 3_600 };

beforeEach(() => invoke.mockReset());

describe('fetchBtcPriceUsd', () => {
  it('returns the feed price when the function answers', async () => {
    invoke.mockResolvedValue({ data: { price: 64_244 }, error: null });
    await expect(fetchBtcPriceUsd()).resolves.toBe(64_244);
  });

  it('returns null — not 0, not 118,000 — when the function errors', async () => {
    invoke.mockResolvedValue({ data: null, error: { message: 'Function not found' } });

    const price = await fetchBtcPriceUsd();
    expect(price).toBeUnknownNotZero();
    expect(price).not.toBe(0);
    expect(price).not.toBe(REMOVED_CONSTANTS.BTC_USD);
  });

  it('returns null when the response carries no price', async () => {
    invoke.mockResolvedValue({ data: {}, error: null });
    await expect(fetchBtcPriceUsd()).resolves.toBeUnknownNotZero();

    invoke.mockResolvedValue({ data: null, error: null });
    await expect(fetchBtcPriceUsd()).resolves.toBeUnknownNotZero();
  });

  it('rejects a price of 0 rather than passing it through', async () => {
    // The feed answering 0 is a broken feed, not a free bitcoin. Passing it on
    // would value the whole reserve at nothing on the risk console.
    invoke.mockResolvedValue({ data: { price: 0 }, error: null });
    await expect(fetchBtcPriceUsd()).resolves.toBeUnknownNotZero();
  });

  it('rejects a negative price', async () => {
    invoke.mockResolvedValue({ data: { price: -1 }, error: null });
    await expect(fetchBtcPriceUsd()).resolves.toBeUnknownNotZero();
  });

  it('rejects NaN, Infinity and a numeric string', async () => {
    for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, '64244']) {
      invoke.mockResolvedValue({ data: { price: bad }, error: null });
      await expect(fetchBtcPriceUsd(), String(bad)).resolves.toBeUnknownNotZero();
    }
  });

  it('calls the btc-price function and nothing else', async () => {
    invoke.mockResolvedValue({ data: { price: 1 }, error: null });
    await fetchBtcPriceUsd();
    expect(invoke).toHaveBeenCalledTimes(1);
    expect(invoke).toHaveBeenCalledWith('btc-price');
  });

  it('shares one query key so two consumers cannot fetch two different prices', () => {
    // The original defect was two sources of truth for one number. A stable key
    // is what keeps the reserves page and the risk console on the same fetch.
    expect(btcPriceKey).toEqual(['btc-price']);
  });
});

describe('fetchEthPriceUsd', () => {
  const ok = (price: number) => ({
    data: { success: true, data: { ETH: { price } } },
    error: null,
  });

  it('returns the feed price when the function answers', async () => {
    invoke.mockResolvedValue(ok(1_932.25));
    await expect(fetchEthPriceUsd()).resolves.toBe(1_932.25);
  });

  it('returns null — not 0, not 3,600 — when the function errors', async () => {
    invoke.mockResolvedValue({ data: null, error: { message: 'upstream 503' } });

    const price = await fetchEthPriceUsd();
    expect(price).toBeUnknownNotZero();
    expect(price).not.toBe(0);
    expect(price).not.toBe(REMOVED_CONSTANTS.ETH_USD);
  });

  it('treats the function\'s own fallback response as a failure', async () => {
    // crypto-prices emits { fallback: true } when every upstream API failed,
    // and the table it then returns is derived from a randomised STR figure.
    // A derived price is not a price — parsing it would put a number on screen
    // that no source stands behind, which is the exact F-035 failure.
    invoke.mockResolvedValue({
      data: { success: true, fallback: true, data: { ETH: { price: 3_600 } } },
      error: null,
    });

    const price = await fetchEthPriceUsd();
    expect(price).toBeUnknownNotZero();
    expect(price).not.toBe(3_600);
  });

  it('returns null when the response carries no ETH entry', async () => {
    invoke.mockResolvedValue({ data: { success: true, data: { BTC: { price: 64_244 } } }, error: null });
    await expect(fetchEthPriceUsd()).resolves.toBeUnknownNotZero();

    invoke.mockResolvedValue({ data: { success: true, data: {} }, error: null });
    await expect(fetchEthPriceUsd()).resolves.toBeUnknownNotZero();

    invoke.mockResolvedValue({ data: null, error: null });
    await expect(fetchEthPriceUsd()).resolves.toBeUnknownNotZero();
  });

  it('rejects a zero, negative or non-numeric ETH price', async () => {
    for (const bad of [0, -5, Number.NaN, '1932.25', null]) {
      invoke.mockResolvedValue({ data: { data: { ETH: { price: bad } } }, error: null });
      await expect(fetchEthPriceUsd(), String(bad)).resolves.toBeUnknownNotZero();
    }
  });

  it('asks crypto-prices for ETH specifically', async () => {
    invoke.mockResolvedValue(ok(1));
    await fetchEthPriceUsd();
    expect(invoke).toHaveBeenCalledWith('crypto-prices', { body: { symbols: 'ETH' } });
  });

  it('shares one query key', () => {
    expect(ethPriceKey).toEqual(['eth-price']);
  });
});

describe('the two feeds are independent', () => {
  it('a BTC failure does not take the ETH price with it, and vice versa', async () => {
    // They are separate edge functions. Collapsing both to one "prices are
    // down" state would hide a working feed behind a broken one.
    invoke.mockImplementation((fn: string) =>
      fn === 'btc-price'
        ? Promise.resolve({ data: null, error: { message: 'down' } })
        : Promise.resolve({ data: { data: { ETH: { price: 1_932.25 } } }, error: null })
    );

    await expect(fetchBtcPriceUsd()).resolves.toBeUnknownNotZero();
    await expect(fetchEthPriceUsd()).resolves.toBe(1_932.25);
  });

  it('neither feed ever answers with the other\'s figure', async () => {
    invoke.mockImplementation((fn: string) =>
      fn === 'btc-price'
        ? Promise.resolve({ data: { price: 64_244 }, error: null })
        : Promise.resolve({ data: { data: { ETH: { price: 1_932.25 } } }, error: null })
    );

    expect(await fetchBtcPriceUsd()).toBe(64_244);
    expect(await fetchEthPriceUsd()).toBe(1_932.25);
  });
});
