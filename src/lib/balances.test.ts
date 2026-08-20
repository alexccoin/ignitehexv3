import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Unit arithmetic.
 *
 * This is the highest-value file in the suite. The defect it guards has shipped
 * three times (docs/FINDINGS.md F-015, F-032):
 *
 *   1. a tile that summed CCOS + STR and printed the total labelled "STR";
 *   2. `total = liquid + staked + rewards`, which counted one holding up to
 *      three times — investor1 held 13,184 STR and the wallet said 26,834;
 *   3. `staked_amount || balance`, which reported a pool with nothing staked as
 *      having its entire liquid balance staked.
 *
 * Each of the three has a test below that goes red if it returns, written
 * against the numbers the defect was actually measured with rather than against
 * round fixtures, so a failure names the real bug.
 */

const rpc = vi.fn();
vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...args: unknown[]) => rpc(...args) },
  isLocal: true,
}));

import {
  positionsFromPools,
  largestPosition,
  byToken,
  byUnit,
  fetchAvailable,
  type StakingPool,
  type EscrowRow,
} from './balances';
import { token as fmtToken } from './format';

/** A staking pool row with only the columns this module reads. */
const pool = (p: Partial<StakingPool> & { pool_type: string }): StakingPool =>
  ({
    balance: 0,
    staked_amount: 0,
    rewards_earned: 0,
    ...p,
  }) as StakingPool;

const escrow = (asset: string, amount: number, status = 'locked'): EscrowRow =>
  ({ asset_symbol: asset, amount, status }) as EscrowRow;

const find = (positions: ReturnType<typeof positionsFromPools>, t: string) => {
  const p = positions.find((x) => x.token === t);
  if (!p) throw new Error(`no position for ${t} in ${positions.map((x) => x.token).join(',')}`);
  return p;
};

/* ------------------------------------------------------------------ */
/* positionsFromPools — the three buckets stay three buckets           */
/* ------------------------------------------------------------------ */

describe('positionsFromPools', () => {
  it('keeps liquid, staked and rewards independent of one another', () => {
    const [p] = positionsFromPools([
      pool({ pool_type: 'str', balance: 13_184, staked_amount: 13_184, rewards_earned: 466 }),
    ]);

    expect(p.liquid).toBe(13_184);
    expect(p.staked).toBe(13_184);
    expect(p.rewards).toBe(466);

    // Each is readable on its own. None is derived from, or overwritten by,
    // another — which is what "independent" has to mean for the labels on the
    // wallet tiles to be true statements.
    expect(p.liquid).not.toBe(p.liquid + p.staked);
    expect(p.staked).not.toBe(0);
  });

  it('F-032: total is liquid + escrowed, NEVER liquid + staked + rewards', () => {
    // The exact production row that produced the wrong figure. credit_voucher_tokens
    // writes the same quantity to balance AND staked_amount for one credit, and
    // calculate_daily_rewards adds each reward to rewards_earned AND to balance.
    // Adding the three columns therefore counts one holding up to three times.
    const [p] = positionsFromPools([
      pool({ pool_type: 'str', balance: 13_184, staked_amount: 13_184, rewards_earned: 466 }),
    ]);

    expect(p.total).toBe(13_184);
    expect(p.total).not.toBe(26_834); // liquid + staked + rewards, the shipped bug
    expect(p.total).not.toBe(26_368); // liquid + staked
    expect(p.total).toBe(p.liquid + p.escrowed);
  });

  it('does not treat staked_amount as a fallback for balance, or the reverse', () => {
    // v2's DomeOverview used `staked_amount || balance`, so a pool with nothing
    // staked reported its whole liquid balance as staked.
    const [p] = positionsFromPools([
      pool({ pool_type: 'ccos', balance: 5_000, staked_amount: 0, rewards_earned: 0 }),
    ]);

    expect(p.staked).toBe(0);
    expect(p.staked).not.toBe(5_000);
    expect(p.liquid).toBe(5_000);
    expect(p.total).toBe(5_000);
  });

  it('never merges two tokens into one position', () => {
    const positions = positionsFromPools([
      pool({ pool_type: 'ccos', balance: 23_542 }),
      pool({ pool_type: 'str', balance: 500 }),
    ]);

    expect(positions).toHaveLength(2);
    expect(positions.map((p) => p.token).sort()).toEqual(['ccos', 'str']);
    // The cross-token total that F-015 printed. No position may carry it.
    expect(positions.some((p) => p.total === 24_042)).toBe(false);
  });

  it('folds several pools of the SAME token, per column', () => {
    const positions = positionsFromPools([
      pool({ pool_type: 'str', balance: 100, staked_amount: 100, rewards_earned: 1 }),
      pool({ pool_type: 'str', balance: 50, staked_amount: 50, rewards_earned: 2 }),
    ]);

    expect(positions).toHaveLength(1);
    expect(positions[0]).toMatchObject({ liquid: 150, staked: 150, rewards: 3, total: 150 });
  });

  it('is case-insensitive about the token and defaults an absent one to "unknown"', () => {
    const positions = positionsFromPools([
      pool({ pool_type: 'STR', balance: 10 }),
      pool({ pool_type: 'str', balance: 5 }),
      pool({ pool_type: null as unknown as string, balance: 1 }),
    ]);

    expect(find(positions, 'str').liquid).toBe(15);
    expect(find(positions, 'unknown').liquid).toBe(1);
  });

  it('coerces null and non-numeric columns to 0 rather than producing NaN', () => {
    // A NaN total sorts unpredictably and renders as "NaN STR". Silently
    // dropping the row would be worse, so it has to become 0.
    const [p] = positionsFromPools([
      pool({
        pool_type: 'str',
        balance: null as unknown as number,
        staked_amount: 'not a number' as unknown as number,
        rewards_earned: undefined as unknown as number,
      }),
    ]);

    expect(p.liquid).toBe(0);
    expect(p.staked).toBe(0);
    expect(p.rewards).toBe(0);
    expect(Number.isNaN(p.total)).toBe(false);
  });

  it('counts only LOCKED escrow, and counts it into total', () => {
    const positions = positionsFromPools(
      [pool({ pool_type: 'str', balance: 1_000 })],
      [escrow('str', 250, 'locked'), escrow('str', 9_999, 'released')]
    );

    const str = find(positions, 'str');
    expect(str.escrowed).toBe(250);
    expect(str.total).toBe(1_250);
  });

  it('opens a position for a token held only in escrow', () => {
    // Otherwise tokens sold but not yet settled vanish from the wallet
    // entirely, which reads as "your funds are gone".
    const positions = positionsFromPools([], [escrow('ccos', 42)]);
    expect(find(positions, 'ccos')).toMatchObject({ liquid: 0, escrowed: 42, total: 42 });
  });

  it('returns an empty array, not null, for a member with no pools', () => {
    expect(positionsFromPools([])).toEqual([]);
  });

  it('sorts by total, largest first', () => {
    const positions = positionsFromPools([
      pool({ pool_type: 'str', balance: 10 }),
      pool({ pool_type: 'ccos', balance: 900 }),
      pool({ pool_type: 'domain', balance: 100 }),
    ]);
    expect(positions.map((p) => p.token)).toEqual(['ccos', 'domain', 'str']);
  });

  it('leaves `available` null until the server has answered', () => {
    // A 0 here would be read as "nothing spendable" and the wallet computes
    // locked = total - available from it.
    const [p] = positionsFromPools([pool({ pool_type: 'str', balance: 1_000 })]);
    expect(p.available).toBeUnknownNotZero();
  });
});

/* ------------------------------------------------------------------ */
/* largestPosition — a headline that is true, not a sum                */
/* ------------------------------------------------------------------ */

describe('largestPosition', () => {
  it('returns null for empty input rather than throwing or inventing a zero', () => {
    // `[].reduce(fn)` with no initial value throws. A tile that throws takes
    // the whole dashboard down for every member who holds nothing.
    expect(largestPosition([])).toBeNull();
  });

  it('returns the single largest holding, never a cross-token sum', () => {
    const positions = positionsFromPools([
      pool({ pool_type: 'ccos', balance: 23_542 }),
      pool({ pool_type: 'str', balance: 500 }),
    ]);

    const biggest = largestPosition(positions);
    expect(biggest?.token).toBe('ccos');
    expect(biggest?.total).toBe(23_542);
    expect(biggest?.total).not.toBe(24_042);
  });

  it('picks the max even when the array is not sorted', () => {
    const unsorted = [
      { token: 'str', liquid: 1, staked: 0, rewards: 0, escrowed: 0, total: 1, available: null },
      { token: 'ccos', liquid: 9, staked: 0, rewards: 0, escrowed: 0, total: 9, available: null },
    ];
    expect(largestPosition(unsorted)?.token).toBe('ccos');
  });

  it('handles a single position', () => {
    const positions = positionsFromPools([pool({ pool_type: 'str', balance: 7 })]);
    expect(largestPosition(positions)?.token).toBe('str');
  });
});

/* ------------------------------------------------------------------ */
/* byToken — the rendering half of the same rule                       */
/* ------------------------------------------------------------------ */

describe('byToken', () => {
  const positions = positionsFromPools([
    pool({ pool_type: 'ccos', balance: 23_542, staked_amount: 23_542, rewards_earned: 12 }),
    pool({ pool_type: 'str', balance: 500, staked_amount: 500, rewards_earned: 3 }),
  ]);

  it('F-015: never renders a single cross-token figure', () => {
    const out = byToken(positions, 'total', fmtToken);

    // Both units are named...
    expect(out).toContain('CCOS');
    expect(out).toContain('STR');
    // ...and the sum that has no unit appears nowhere.
    expect(out).not.toContain('24,042');
    expect(out).toBe('23,542 CCOS · 500 STR');
  });

  it('never labels the sum with one token\'s symbol', () => {
    // The precise shape of the shipped bug: 23,542 + 500 printed as "24,042 STR".
    const out = byToken(positions, 'total', fmtToken);
    expect(out).not.toMatch(/24,042\s*(STR|CCOS)/);
  });

  it('names every unit it is given, or says how many it omitted', () => {
    // Silently dropping a token is the same defect wearing a quieter face: the
    // member cannot tell a holding they do not have from one that was not shown.
    const many = positionsFromPools([
      pool({ pool_type: 'ccos', balance: 4 }),
      pool({ pool_type: 'str', balance: 3 }),
      pool({ pool_type: 'domain', balance: 2 }),
      pool({ pool_type: 'wstr', balance: 1 }),
    ]);

    const out = byToken(many, 'total', fmtToken, 2);
    expect(out).toBe('4 CCOS · 3 STR +2 more');

    const shownUnits = (out.match(/[A-Za-z]+(?=\b)/g) ?? []).filter((w) => w !== 'more');
    const omitted = Number(out.match(/\+(\d+) more/)?.[1] ?? 0);
    expect(shownUnits.length + omitted).toBe(many.length);
  });

  it('reads each column separately, so the staked tile is not the holdings tile', () => {
    expect(byToken(positions, 'liquid', fmtToken)).toBe('23,542 CCOS · 500 STR');
    expect(byToken(positions, 'staked', fmtToken)).toBe('23,542 CCOS · 500 STR');
    expect(byToken(positions, 'rewards', fmtToken)).toBe('12 CCOS · 3 STR');
    // The rewards tile must not be showing the balance.
    expect(byToken(positions, 'rewards', fmtToken)).not.toContain('23,542');
  });

  it('renders an em dash, not "0", when nothing is held', () => {
    expect(byToken([], 'total', fmtToken)).toBe('—');
    expect(byToken(positions, 'escrowed', fmtToken)).toBe('—');
  });
});

describe('byUnit', () => {
  const fmt = (n: number, unit: string) => `${n} ${unit}`;

  it('folds entries that share a unit instead of listing them twice', () => {
    expect(byUnit([{ unit: 'EUR', amount: 1_000 }, { unit: 'EUR', amount: 500 }], fmt)).toBe(
      '1500 EUR'
    );
  });

  it('keeps different units apart — the fiat form of F-015', () => {
    const out = byUnit([{ unit: 'EUR', amount: 1_000 }, { unit: 'USD', amount: 500 }], fmt);
    expect(out).toBe('1000 EUR · 500 USD');
    expect(out).not.toContain('1500');
  });

  it('orders by amount and truncates with a count', () => {
    expect(
      byUnit(
        [
          { unit: 'GBP', amount: 1 },
          { unit: 'EUR', amount: 3 },
          { unit: 'USD', amount: 2 },
        ],
        fmt,
        2
      )
    ).toBe('3 EUR · 2 USD +1 more');
  });

  it('drops zero and negative amounts rather than printing "0 EUR"', () => {
    expect(byUnit([{ unit: 'EUR', amount: 0 }], fmt)).toBe('—');
    expect(byUnit([], fmt)).toBe('—');
  });
});

/* ------------------------------------------------------------------ */
/* fetchAvailable — a failure is null                                  */
/* ------------------------------------------------------------------ */

describe('fetchAvailable', () => {
  beforeEach(() => rpc.mockReset());

  it('returns the server figure when the RPC succeeds', async () => {
    rpc.mockResolvedValue({ data: 13_184, error: null });
    await expect(fetchAvailable('u', 'str')).resolves.toBe(13_184);
  });

  it('returns 0 when the server genuinely says zero', async () => {
    // The real-zero case has to stay distinguishable from the failure case
    // below, which is the whole point of the null.
    rpc.mockResolvedValue({ data: 0, error: null });
    await expect(fetchAvailable('u', 'str')).resolves.toBe(0);
  });

  it('returns null — not 0 — when the RPC errors', async () => {
    // v2 collapsed both to 0, and the wallet then computed locked = total - 0,
    // displaying a member's entire holding as locked after one failed request.
    rpc.mockResolvedValue({ data: null, error: { message: 'permission denied' } });
    await expect(fetchAvailable('u', 'str')).resolves.toBeUnknownNotZero();
  });

  it('returns null when the RPC answers with no data', async () => {
    rpc.mockResolvedValue({ data: null, error: null });
    await expect(fetchAvailable('u', 'str')).resolves.toBeUnknownNotZero();

    rpc.mockResolvedValue({ data: undefined, error: null });
    await expect(fetchAvailable('u', 'str')).resolves.toBeUnknownNotZero();
  });

  it('returns null when the RPC answers with something that is not a number', async () => {
    rpc.mockResolvedValue({ data: 'lots', error: null });
    await expect(fetchAvailable('u', 'str')).resolves.toBeUnknownNotZero();
  });

  it('asks for the balance of one user and one token', async () => {
    rpc.mockResolvedValue({ data: 1, error: null });
    await fetchAvailable('user-1', 'str');
    expect(rpc).toHaveBeenCalledWith('get_available_balance', {
      p_user_id: 'user-1',
      p_token_type: 'str',
    });
  });
});
