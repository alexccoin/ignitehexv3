import { supabase } from '@/lib/supabase';
import { fetchBtcPriceUsd } from '@/lib/btcPrice';
import { fetchEthPriceUsd } from '@/lib/ethPrice';
import { paginate, type PageResponse } from './paginate';
import { checkCoverage, type CoverageReport } from './coverage';
import { num, tokenUsd, type MarketRates } from './valuation';

/**
 * Platform-wide risk radar.
 *
 * Ported from v2 `src/lib/platformRiskScan.ts`. Scans every asset-bearing table
 * — vouchers, fiat, crypto, staking, shares, SAFE equity, nodes, cards,
 * withdrawals, transfers, exchanges and marketplace escrow — for strange or
 * risky operations and returns a normalised list of findings to triage.
 *
 * Read-only: it never mutates data. Safe mode still governs any push.
 *
 * Ported the same way as the exposure sweep: typed reads with explicit column
 * lists instead of `supabase as any`, unique-key pagination instead of
 * `created_at` ordering, and truncation reported rather than swallowed.
 */

/** Value-driven findings below this USD-equivalent are ignored. */
export const MIN_FINDING_USD = 10_000;

export type RiskSeverity = 'critical' | 'high' | 'medium' | 'low';

export interface RiskFinding {
  id: string;
  severity: RiskSeverity;
  /** Asset class, e.g. "Vouchers", "Fiat", "Crypto". */
  category: string;
  /** Table the finding came from. */
  source: string;
  /** Human rule name. */
  rule: string;
  /** What is strange about it. */
  detail: string;
  userId: string | null;
  amount: number | null;
  unit: string | null;
  reference: string | null;
  createdAt: string | null;
}

export interface RiskScanResult {
  findings: RiskFinding[];
  scannedRows: number;
  scannedTables: string[];
  truncatedTables: string[];
  /**
   * How much of each table this scan was allowed to read. A rule that never
   * fires because RLS hid the rows it would have fired on is worse than a rule
   * that is missing: it reads as a clean scan (F-034).
   */
  coverage: CoverageReport;
  errors: string[];
  ranAt: string;
}

const SEVERITY_WEIGHT: Record<RiskSeverity, number> = {
  critical: 4, high: 3, medium: 2, low: 1,
};

export const severityRank = (severity: RiskSeverity): number => SEVERITY_WEIGHT[severity];

export const SEVERITY_ORDER: RiskSeverity[] = ['critical', 'high', 'medium', 'low'];

/** Value thresholds used across the radar. */
export const RISK_THRESHOLDS = {
  largeUsd: 25_000,
  hugeUsd: 100_000,
  largeTokens: 250_000,
  hugeTokens: 1_000_000,
  stalePendingDays: 14,
} as const;

const daysAgo = (iso: string | null | undefined): number =>
  iso ? Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000) : 0;

const fmt = (value: number): string =>
  value.toLocaleString('en-US', { maximumFractionDigits: 2 });

/**
 * Group rows by a shared key, keeping only the keys that appear more than once.
 *
 * Keys shorter than six characters are ignored: a one-character "reference"
 * shared by two rows is a data-entry artefact, not a duplicated payment.
 */
function dupGroups<T>(rows: T[], key: (row: T) => string | null): [string, T[]][] {
  const map = new Map<string, T[]>();
  for (const row of rows) {
    const value = (key(row) || '').trim().toLowerCase();
    if (!value || value.length < 6) continue;
    const list = map.get(value) ?? [];
    list.push(row);
    map.set(value, list);
  }
  return [...map.entries()].filter(([, list]) => list.length > 1);
}

interface ScanState {
  findings: RiskFinding[];
  scannedTables: string[];
  truncatedTables: string[];
  scannedRows: number;
  errors: string[];
  /** Rows received per table, for the coverage check. See platformExposure. */
  rowsRead: Record<string, number>;
  /** Makes ids unique when two findings share a source, rule and reference. */
  seq: number;
}

/** Read one table and run its rules. A table that fails is recorded, not fatal. */
async function scan<T>(
  state: ScanState,
  table: string,
  load: (from: number, to: number) => PromiseLike<PageResponse<T>>,
  rules: (rows: T[]) => void
): Promise<void> {
  try {
    const { rows, truncated } = await paginate(table, load);
    state.scannedTables.push(table);
    state.scannedRows += rows.length;
    state.rowsRead[table] = (state.rowsRead[table] ?? 0) + rows.length;
    if (truncated) state.truncatedTables.push(table);
    rules(rows);
  } catch (error) {
    state.errors.push(error instanceof Error ? error.message : String(error));
  }
}

export async function runPlatformRiskScan(marketRates?: MarketRates): Promise<RiskScanResult> {
  // The same BTC price the exposure sweep and `/guardian/reserves` use, and
  // the same ETH price the exposure sweep uses. Null when a feed fails, in
  // which case that asset's amounts stay unpriced rather than being valued
  // from a constant. `useRiskScan` supplies both from the shared react-query
  // cache so this scan and the exposure sweep can never disagree about a
  // price; the direct fetch is the fallback for a caller outside React.
  const rates: MarketRates =
    marketRates ?? { btcUsd: await fetchBtcPriceUsd(), ethUsd: await fetchEthPriceUsd() };

  const state: ScanState = {
    findings: [], scannedTables: [], truncatedTables: [], scannedRows: 0, errors: [],
    rowsRead: {}, seq: 0,
  };

  /**
   * v2 built ids as `${source}:${rule}:${reference ?? Math.random()}`, so a
   * finding with no reference got a new key on every scan and React remounted
   * the whole row. The counter makes ids unique and stable within one scan.
   */
  const push = (finding: Omit<RiskFinding, 'id'>): void => {
    state.seq += 1;
    state.findings.push({
      ...finding,
      id: `${finding.source}:${finding.rule}:${finding.reference ?? ''}:${state.seq}`,
    });
  };

  /* ------------------------------ vouchers ----------------------------- */

  await scan(
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
      for (const [hash, list] of dupGroups(rows, (r) => r.payment_hash || r.confirmation_number)) {
        push({
          severity: 'critical',
          category: 'Vouchers',
          source: 'voucher_redemptions',
          rule: 'Duplicate payment proof',
          detail: `${list.length} voucher submissions share the payment reference ${hash.slice(0, 24)}…`,
          userId: list[0].user_id,
          amount: list.reduce((sum, r) => sum + (num(r.credited_amount) || num(r.amount)), 0),
          unit: 'tokens',
          reference: hash,
          createdAt: list[0].created_at,
        });
      }

      for (const row of rows) {
        const credited = num(row.credited_amount);
        const claimed = num(row.amount);

        if (credited > 0 && claimed > 0 && credited > claimed * 1.5) {
          push({
            severity: 'critical',
            category: 'Vouchers',
            source: 'voucher_redemptions',
            rule: 'Credited above declared value',
            detail: `Credited ${fmt(credited)} against a declared ${fmt(claimed)} (${row.token_type})`,
            userId: row.user_id,
            amount: credited,
            unit: row.token_type,
            reference: row.id,
            createdAt: row.created_at,
          });
        }

        if (
          row.status !== 'rejected' &&
          !row.payment_hash &&
          !row.confirmation_number &&
          !row.proof_of_payment_url
        ) {
          push({
            severity: 'high',
            category: 'Vouchers',
            source: 'voucher_redemptions',
            rule: 'No payment proof',
            detail: `${row.package_type} submitted with no hash, confirmation or proof file`,
            userId: row.user_id,
            amount: claimed,
            unit: row.token_type,
            reference: row.id,
            createdAt: row.created_at,
          });
        }

        if (row.status === 'pending' && daysAgo(row.created_at) > RISK_THRESHOLDS.stalePendingDays) {
          push({
            severity: 'low',
            category: 'Vouchers',
            source: 'voucher_redemptions',
            rule: 'Stale pending voucher',
            detail: `Pending for ${daysAgo(row.created_at)} days`,
            userId: row.user_id,
            amount: claimed,
            unit: row.token_type,
            reference: row.id,
            createdAt: row.created_at,
          });
        }
      }
    }
  );

  /* -------------------------------- fiat ------------------------------- */

  await scan(
    state,
    'fiat_wallets',
    (from, to) =>
      supabase
        .from('fiat_wallets')
        .select('id, user_id, currency, balance, available_balance, held_balance, updated_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const balance = num(row.balance);
        const parts = num(row.available_balance) + num(row.held_balance);

        if (balance < 0 || num(row.available_balance) < 0) {
          push({
            severity: 'critical', category: 'Fiat', source: 'fiat_wallets',
            rule: 'Negative balance',
            detail: `${row.currency} wallet holds ${fmt(balance)}`,
            userId: row.user_id, amount: balance, unit: row.currency,
            reference: row.id, createdAt: row.updated_at,
          });
        } else if (Math.abs(balance - parts) > 0.01) {
          push({
            severity: 'high', category: 'Fiat', source: 'fiat_wallets',
            rule: 'Ledger mismatch',
            detail: `balance ${fmt(balance)} ≠ available+held ${fmt(parts)} (${row.currency})`,
            userId: row.user_id, amount: balance - parts, unit: row.currency,
            reference: row.id, createdAt: row.updated_at,
          });
        }

        if (balance >= RISK_THRESHOLDS.hugeUsd) {
          push({
            severity: 'medium', category: 'Fiat', source: 'fiat_wallets',
            rule: 'Very large fiat balance',
            detail: `${fmt(balance)} ${row.currency} held on one account`,
            userId: row.user_id, amount: balance, unit: row.currency,
            reference: row.id, createdAt: row.updated_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'fiat_transactions',
    (from, to) =>
      supabase
        .from('fiat_transactions')
        .select(
          'id, tx_id, from_user_id, to_user_id, currency, amount, status, requires_approval, approved_by, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const amount = num(row.amount);

        if (row.requires_approval && !row.approved_by && row.status !== 'rejected') {
          push({
            severity: amount >= RISK_THRESHOLDS.largeUsd ? 'critical' : 'high',
            category: 'Fiat', source: 'fiat_transactions',
            rule: 'Unapproved transfer needing approval',
            detail: `${fmt(amount)} ${row.currency} still unapproved (${row.status})`,
            userId: row.from_user_id ?? row.to_user_id, amount, unit: row.currency,
            reference: row.tx_id ?? row.id, createdAt: row.created_at,
          });
        }

        if (row.from_user_id && row.from_user_id === row.to_user_id && amount > 0) {
          push({
            severity: 'medium', category: 'Fiat', source: 'fiat_transactions',
            rule: 'Self transfer',
            detail: `Account sent ${fmt(amount)} ${row.currency} to itself`,
            userId: row.from_user_id, amount, unit: row.currency,
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  /* ------------------------------- crypto ------------------------------ */

  await scan(
    state,
    'crypto_wallets',
    (from, to) =>
      supabase
        .from('crypto_wallets')
        .select('id, user_id, token_type, balance, available_balance, held_balance, updated_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const balance = num(row.balance);

        if (balance < 0) {
          push({
            severity: 'critical', category: 'Crypto', source: 'crypto_wallets',
            rule: 'Negative token balance',
            detail: `${fmt(balance)} ${row.token_type}`,
            userId: row.user_id, amount: balance, unit: row.token_type,
            reference: row.id, createdAt: row.updated_at,
          });
        } else if (balance >= RISK_THRESHOLDS.hugeTokens) {
          push({
            severity: 'high', category: 'Crypto', source: 'crypto_wallets',
            rule: 'Outsized token balance',
            detail: `${fmt(balance)} ${row.token_type} on one wallet`,
            userId: row.user_id, amount: balance, unit: row.token_type,
            reference: row.id, createdAt: row.updated_at,
          });
        }

        const parts = num(row.available_balance) + num(row.held_balance);
        if (balance > 0 && parts > 0 && Math.abs(balance - parts) > 0.01) {
          push({
            severity: 'medium', category: 'Crypto', source: 'crypto_wallets',
            rule: 'Ledger mismatch',
            detail: `balance ${fmt(balance)} ≠ available+held ${fmt(parts)}`,
            userId: row.user_id, amount: balance - parts, unit: row.token_type,
            reference: row.id, createdAt: row.updated_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'wallet_transactions',
    (from, to) =>
      supabase
        .from('wallet_transactions')
        .select(
          'id, from_user_id, to_user_id, amount, token_type, transaction_hash, status, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const [hash, list] of dupGroups(rows, (r) => r.transaction_hash)) {
        push({
          severity: 'high', category: 'Crypto', source: 'wallet_transactions',
          rule: 'Reused transaction hash',
          detail: `${list.length} wallet transactions share hash ${hash.slice(0, 20)}…`,
          userId: list[0].from_user_id ?? list[0].to_user_id,
          amount: list.reduce((sum, r) => sum + num(r.amount), 0),
          unit: list[0].token_type, reference: hash, createdAt: list[0].created_at,
        });
      }

      for (const row of rows) {
        const amount = num(row.amount);
        if (amount >= RISK_THRESHOLDS.largeTokens && row.status !== 'failed') {
          push({
            severity: 'medium', category: 'Crypto', source: 'wallet_transactions',
            rule: 'Large token movement',
            detail: `${fmt(amount)} ${row.token_type} moved (${row.status})`,
            userId: row.from_user_id, amount, unit: row.token_type,
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'token_transfers',
    (from, to) =>
      supabase
        .from('token_transfers')
        .select('id, sender_id, recipient_id, token_type, amount, status, transaction_hash, created_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const amount = num(row.amount);

        if (row.sender_id && row.sender_id === row.recipient_id) {
          push({
            severity: 'medium', category: 'Crypto', source: 'token_transfers',
            rule: 'Self transfer',
            detail: `${fmt(amount)} ${row.token_type} to self`,
            userId: row.sender_id, amount, unit: row.token_type,
            reference: row.id, createdAt: row.created_at,
          });
        }

        if (row.status === 'pending' && daysAgo(row.created_at) > RISK_THRESHOLDS.stalePendingDays) {
          push({
            severity: 'low', category: 'Crypto', source: 'token_transfers',
            rule: 'Stale pending transfer',
            detail: `Pending ${daysAgo(row.created_at)} days · ${fmt(amount)} ${row.token_type}`,
            userId: row.sender_id, amount, unit: row.token_type,
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  /* ------------------------------ exchanges ---------------------------- */

  await scan(
    state,
    'currency_exchanges',
    (from, to) =>
      supabase
        .from('currency_exchanges')
        .select(
          'id, user_id, from_currency, to_currency, from_amount, to_amount, exchange_rate, status, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const fromAmount = num(row.from_amount);
        const toAmount = num(row.to_amount);
        const rate = num(row.exchange_rate);
        if (fromAmount <= 0 || rate <= 0) continue;

        const expected = fromAmount * rate;
        if (expected > 0 && Math.abs(toAmount - expected) / expected > 0.02) {
          push({
            severity: 'critical', category: 'Exchange', source: 'currency_exchanges',
            rule: 'Rate / amount mismatch',
            detail: `${fmt(fromAmount)} ${row.from_currency} → ${fmt(toAmount)} ${row.to_currency}, expected ${fmt(expected)} at rate ${rate}`,
            userId: row.user_id, amount: toAmount - expected, unit: row.to_currency,
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'crypto_orders',
    (from, to) =>
      supabase
        .from('crypto_orders')
        .select(
          'id, user_id, token_symbol, package_amount_usd, token_amount, status, coinpayments_txn_id, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (row.status === 'completed' && !row.coinpayments_txn_id) {
          push({
            severity: 'high', category: 'Exchange', source: 'crypto_orders',
            rule: 'Completed without payment id',
            detail: `${fmt(num(row.token_amount))} ${row.token_symbol} marked completed with no processor reference`,
            userId: row.user_id, amount: num(row.package_amount_usd), unit: 'USD',
            reference: row.id, createdAt: row.created_at,
          });
        }

        if (num(row.package_amount_usd) >= RISK_THRESHOLDS.hugeUsd) {
          push({
            severity: 'medium', category: 'Exchange', source: 'crypto_orders',
            rule: 'Very large order',
            detail: `${fmt(num(row.package_amount_usd))} USD order (${row.status})`,
            userId: row.user_id, amount: num(row.package_amount_usd), unit: 'USD',
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'cross_border_payments',
    (from, to) =>
      supabase
        .from('cross_border_payments')
        .select('id, user_id, amount, currency, status, compliance_score, receiver_country, created_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const score = num(row.compliance_score);
        if (score > 0 && score < 50) {
          push({
            severity: 'high', category: 'Payments', source: 'cross_border_payments',
            rule: 'Low compliance score',
            detail: `Score ${score} on ${fmt(num(row.amount))} ${row.currency} to ${row.receiver_country ?? '—'}`,
            userId: row.user_id, amount: num(row.amount), unit: row.currency,
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  /* -------------------------- staking & shares ------------------------- */

  /**
   * Admin credit is the ONLY truth for staking / shares / vesting.
   *
   * What each member holds in those tables is tallied and compared against what
   * an admin actually credited — credited vouchers, credited raises, and
   * admin-approved staking requests. Anything above that is unbacked: a
   * position the platform is carrying with no record of anyone granting it.
   */
  const positionsUsd = new Map<string, number>();
  const creditUsd = new Map<string, number>();

  /**
   * `value` is null when nothing prices the unit, in which case the holding
   * contributes no USD - it is not silently valued at the STR rate the way
   * tokenUsd's old fallback did. The unbacked comparison below is therefore a
   * comparison of the priceable half only, which the caller is told about.
   */
  const bump = (
    map: Map<string, number>,
    key: string | null | undefined,
    value: number | null
  ): void => {
    if (!key || value === null || !Number.isFinite(value) || value === 0) return;
    map.set(key, (map.get(key) ?? 0) + value);
  };

  await scan(
    state,
    'user_staking_pools',
    (from, to) =>
      supabase
        .from('user_staking_pools')
        .select('id, user_id, pool_type, balance, staked_amount, rewards_earned, status, updated_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
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
        const balance = num(row.balance);
        const held = row.balance === null ? num(row.staked_amount) : balance;
        bump(positionsUsd, row.user_id, tokenUsd(row.pool_type, held, rates));

        if (balance < 0) {
          push({
            severity: 'critical', category: 'Staking', source: 'user_staking_pools',
            rule: 'Negative pool balance',
            detail: `${row.pool_type}: ${fmt(balance)}`,
            userId: row.user_id, amount: balance, unit: row.pool_type,
            reference: row.id, createdAt: row.updated_at,
          });
        }

        if (num(row.rewards_earned) > balance * 2 && num(row.rewards_earned) > 1000) {
          push({
            severity: 'high', category: 'Staking', source: 'user_staking_pools',
            rule: 'Rewards exceed principal',
            detail: `${fmt(num(row.rewards_earned))} rewards vs ${fmt(balance)} balance in ${row.pool_type}`,
            userId: row.user_id, amount: num(row.rewards_earned), unit: row.pool_type,
            reference: row.id, createdAt: row.updated_at,
          });
        }

        if (balance >= RISK_THRESHOLDS.hugeTokens) {
          push({
            severity: 'medium', category: 'Staking', source: 'user_staking_pools',
            rule: 'Outsized pool position',
            detail: `${fmt(balance)} in ${row.pool_type}`,
            userId: row.user_id, amount: balance, unit: row.pool_type,
            reference: row.id, createdAt: row.updated_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'user_str_shares',
    (from, to) =>
      supabase
        .from('user_str_shares')
        .select('id, user_id, balance, locked_balance, wnft_shares, updated_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const balance = num(row.balance);
        const locked = num(row.locked_balance);
        bump(positionsUsd, row.user_id, tokenUsd('STR', balance + locked, rates));

        if (balance < 0 || locked < 0) {
          push({
            severity: 'critical', category: 'Shares', source: 'user_str_shares',
            rule: 'Negative share balance',
            detail: `balance ${fmt(balance)} · locked ${fmt(locked)}`,
            userId: row.user_id, amount: balance, unit: 'shares',
            reference: row.id, createdAt: row.updated_at,
          });
        }

        if (locked > balance + 0.01) {
          push({
            severity: 'high', category: 'Shares', source: 'user_str_shares',
            rule: 'Locked exceeds balance',
            detail: `locked ${fmt(locked)} > balance ${fmt(balance)}`,
            userId: row.user_id, amount: locked - balance, unit: 'shares',
            reference: row.id, createdAt: row.updated_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'vesting_tokens',
    (from, to) =>
      supabase
        .from('vesting_tokens')
        .select('id, user_id, token_type, amount, status, created_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (String(row.status ?? '').toLowerCase() === 'cancelled') continue;
        bump(positionsUsd, row.user_id, tokenUsd(row.token_type, num(row.amount), rates));
      }
    }
  );

  /* ----------------- admin credit ledger (the single truth) -------------- */

  await scan(
    state,
    'voucher_redemptions',
    (from, to) =>
      supabase
        .from('voucher_redemptions')
        .select('id, user_id, token_type, credited_amount, tokens_credited, credited_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (!row.tokens_credited && !row.credited_at) continue;
        bump(creditUsd, row.user_id, tokenUsd(row.token_type, num(row.credited_amount), rates));
      }
    }
  );

  await scan(
    state,
    'seed_str_applications',
    (from, to) =>
      supabase
        .from('seed_str_applications')
        .select(
          'id, user_id, investment_amount, credited_amount, payment_amount, str_shares_credited, credited_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (!row.credited_at) continue;
        const tokens =
          num(row.credited_amount) || num(row.str_shares_credited) || num(row.investment_amount);
        bump(creditUsd, row.user_id, num(row.payment_amount) || tokenUsd('STR', tokens, rates));
      }
    }
  );

  await scan(
    state,
    'private_seed_str_applications',
    (from, to) =>
      supabase
        .from('private_seed_str_applications')
        .select(
          'id, user_id, investment_amount, credited_amount, payment_amount, str_shares_credited, credited_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (!row.credited_at) continue;
        const tokens =
          num(row.credited_amount) || num(row.str_shares_credited) || num(row.investment_amount);
        bump(creditUsd, row.user_id, num(row.payment_amount) || tokenUsd('STR', tokens, rates));
      }
    }
  );

  await scan(
    state,
    'staking_requests',
    (from, to) =>
      supabase
        .from('staking_requests')
        .select('id, user_id, pool_type, amount, status, approved_by, processed_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const status = String(row.status ?? '').toLowerCase();
        if (!['approved', 'completed', 'credited', 'processed'].includes(status)) continue;
        if (!row.approved_by) continue;
        bump(creditUsd, row.user_id, tokenUsd(row.pool_type, num(row.amount), rates));
      }
    }
  );

  positionsUsd.forEach((held, userId) => {
    const credited = creditUsd.get(userId) ?? 0;
    const unbacked = held - credited;
    if (unbacked < MIN_FINDING_USD) return;

    push({
      severity:
        credited <= 0 ? 'critical' : unbacked >= RISK_THRESHOLDS.hugeUsd ? 'high' : 'medium',
      category: 'Credit backing',
      source: 'user_staking_pools',
      rule: credited <= 0 ? 'Positions with no admin credit' : 'Positions exceed admin credit',
      detail: `staking/shares/vesting worth $${fmt(Math.round(held))} vs $${fmt(Math.round(credited))} credited by admins — $${fmt(Math.round(unbacked))} unbacked`,
      userId,
      amount: Math.round(unbacked),
      unit: 'USD',
      reference: userId,
      createdAt: null,
    });
  });

  /* ------------------------------- equity ------------------------------ */

  await scan(
    state,
    'safe_purchases',
    (from, to) =>
      supabase
        .from('safe_purchases')
        .select(
          'id, user_id, total_shares, credited_shares, total_usd, bonus_pct, status, tx_hash, credited_at, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const [hash, list] of dupGroups(rows, (r) => r.tx_hash)) {
        push({
          severity: 'critical', category: 'SAFE equity', source: 'safe_purchases',
          rule: 'Duplicate SAFE tx hash',
          detail: `${list.length} subscriptions share tx ${hash.slice(0, 20)}…`,
          userId: list[0].user_id,
          amount: list.reduce((sum, r) => sum + num(r.total_usd), 0),
          unit: 'USD', reference: hash, createdAt: list[0].created_at,
        });
      }

      for (const row of rows) {
        if (row.credited_at && num(row.credited_shares) !== num(row.total_shares)) {
          push({
            severity: 'high', category: 'SAFE equity', source: 'safe_purchases',
            rule: 'Credited shares mismatch',
            detail: `credited ${fmt(num(row.credited_shares))} vs subscribed ${fmt(num(row.total_shares))}`,
            userId: row.user_id, amount: num(row.total_usd), unit: 'USD',
            reference: row.id, createdAt: row.created_at,
          });
        }

        if (num(row.bonus_pct) > 25) {
          push({
            severity: 'medium', category: 'SAFE equity', source: 'safe_purchases',
            rule: 'Bonus above policy',
            detail: `${num(row.bonus_pct)}% bonus applied`,
            userId: row.user_id, amount: num(row.total_usd), unit: 'USD',
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  /* -------------------------------- nodes ------------------------------ */

  await scan(
    state,
    'starw_purchases',
    (from, to) =>
      supabase
        .from('starw_purchases')
        .select('id, user_id, node_count, total_cost, status, created_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (num(row.total_cost) >= RISK_THRESHOLDS.largeUsd) {
          push({
            severity: 'medium', category: 'Nodes', source: 'starw_purchases',
            rule: 'Large STARW order',
            detail: `${num(row.node_count)} nodes · ${fmt(num(row.total_cost))} USD (${row.status})`,
            userId: row.user_id, amount: num(row.total_cost), unit: 'USD',
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'supernode_purchases',
    (from, to) =>
      supabase
        .from('supernode_purchases')
        .select('id, user_id, supernode_count, total_cost, status, transaction_hash, created_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const [hash, list] of dupGroups(rows, (r) => r.transaction_hash)) {
        push({
          severity: 'high', category: 'Nodes', source: 'supernode_purchases',
          rule: 'Duplicate supernode tx hash',
          detail: `${list.length} supernode orders share hash ${hash.slice(0, 20)}…`,
          userId: list[0].user_id,
          amount: list.reduce((sum, r) => sum + num(r.total_cost), 0),
          unit: 'USD', reference: hash, createdAt: list[0].created_at,
        });
      }
    }
  );

  /* ----------------------------- withdrawals --------------------------- */

  await scan(
    state,
    'withdrawal_requests',
    (from, to) =>
      supabase
        .from('withdrawal_requests')
        .select(
          'id, user_id, withdrawal_address, btc_amount, usd_value_at_request, status, requested_at, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      const live = rows.filter((row) => row.status !== 'rejected');

      for (const [address, list] of dupGroups(live, (r) => r.withdrawal_address)) {
        const users = new Set(list.map((row) => row.user_id));
        if (users.size <= 1) continue;
        push({
          severity: 'critical', category: 'Withdrawals', source: 'withdrawal_requests',
          rule: 'Address shared by accounts',
          detail: `${users.size} accounts withdraw to ${address.slice(0, 16)}…`,
          userId: list[0].user_id,
          amount: list.reduce((sum, row) => sum + num(row.btc_amount), 0),
          unit: 'BTC', reference: address, createdAt: list[0].created_at,
        });
      }

      for (const row of rows) {
        if (row.status === 'pending' && num(row.usd_value_at_request) >= RISK_THRESHOLDS.largeUsd) {
          push({
            severity: 'high', category: 'Withdrawals', source: 'withdrawal_requests',
            rule: 'Large pending withdrawal',
            detail: `${fmt(num(row.btc_amount))} BTC (${fmt(num(row.usd_value_at_request))} USD) awaiting release`,
            userId: row.user_id, amount: num(row.usd_value_at_request), unit: 'USD',
            reference: row.id, createdAt: row.created_at,
          });
        }
      }
    }
  );

  /* ---------------------------- cards & vaults ------------------------- */

  await scan(
    state,
    'prepaid_cards',
    (from, to) =>
      supabase
        .from('prepaid_cards')
        .select('id, user_id, currency, balance, status, card_status, updated_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const balance = num(row.balance);
        if (balance < 0) {
          push({
            severity: 'critical', category: 'Cards', source: 'prepaid_cards',
            rule: 'Negative card balance',
            detail: `${fmt(balance)} ${row.currency}`,
            userId: row.user_id, amount: balance, unit: row.currency,
            reference: row.id, createdAt: row.updated_at,
          });
        } else if (balance >= RISK_THRESHOLDS.largeUsd) {
          push({
            severity: 'medium', category: 'Cards', source: 'prepaid_cards',
            rule: 'Large card balance',
            detail: `${fmt(balance)} ${row.currency} on a ${row.status || row.card_status || 'card'}`,
            userId: row.user_id, amount: balance, unit: row.currency,
            reference: row.id, createdAt: row.updated_at,
          });
        }
      }
    }
  );

  await scan(
    state,
    'guardian_wallets',
    (from, to) =>
      supabase
        .from('guardian_wallets')
        .select('id, user_id, asset_symbol, balance, external_balance, usd_value, updated_at')
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        if (num(row.balance) < 0) {
          push({
            severity: 'critical', category: 'Guardian', source: 'guardian_wallets',
            rule: 'Negative guardian balance',
            detail: `${fmt(num(row.balance))} ${row.asset_symbol}`,
            userId: row.user_id, amount: num(row.balance), unit: row.asset_symbol,
            reference: row.id, createdAt: row.updated_at,
          });
        }

        if (num(row.usd_value) >= RISK_THRESHOLDS.hugeUsd) {
          push({
            severity: 'medium', category: 'Guardian', source: 'guardian_wallets',
            rule: 'High-value guardian vault',
            detail: `${fmt(num(row.balance))} ${row.asset_symbol} ≈ ${fmt(num(row.usd_value))} USD`,
            userId: row.user_id, amount: num(row.usd_value), unit: 'USD',
            reference: row.id, createdAt: row.updated_at,
          });
        }
      }
    }
  );

  /* ---------------------------- marketplace ---------------------------- */

  await scan(
    state,
    'domain_marketplace_transactions',
    (from, to) =>
      supabase
        .from('domain_marketplace_transactions')
        .select(
          'id, seller_id, buyer_id, sale_price, currency, status, escrow_status, expires_at, created_at'
        )
        .order('id', { ascending: true })
        .range(from, to),
    (rows) => {
      for (const row of rows) {
        const expired = row.expires_at !== null && new Date(row.expires_at).getTime() < Date.now();
        if (!expired || row.status === 'completed' || row.status === 'cancelled') continue;

        push({
          severity: 'medium', category: 'Marketplace', source: 'domain_marketplace_transactions',
          rule: 'Expired escrow still open',
          detail: `${fmt(num(row.sale_price))} ${row.currency} · escrow ${row.escrow_status} · status ${row.status}`,
          userId: row.buyer_id ?? row.seller_id, amount: num(row.sale_price), unit: row.currency,
          reference: row.id, createdAt: row.created_at,
        });
      }
    }
  );

  /* ------------------------ material-value filter ----------------------- */

  // Integrity breaches are always kept, whatever they are worth — a duplicated
  // payment proof for $50 is the same fraud as one for $50,000. Every other
  // finding must clear $10,000 USD-equivalent so ordinary accounts stay out of
  // a queue meant for the accounts that matter.
  const ALWAYS_KEEP = /duplicate|reused|negative|mismatch|shared by accounts|without payment|no payment proof/i;

  const material = state.findings.filter((finding) => {
    if (ALWAYS_KEEP.test(finding.rule)) return true;

    // A finding whose unit has no USD rate is KEPT, not dropped. The filter
    // exists to hide small amounts, and "we cannot price this" is not evidence
    // that the amount is small - dropping it would make an unpriceable holding
    // disappear from the queue entirely. The finding still carries its own
    // unit, so the triage screen shows what it is denominated in.
    const usd = tokenUsd(finding.unit, finding.amount ?? 0, rates);
    if (usd === null) return true;
    return Math.abs(usd) >= MIN_FINDING_USD;
  });

  material.sort((a, b) => {
    const bySeverity = severityRank(b.severity) - severityRank(a.severity);
    if (bySeverity !== 0) return bySeverity;
    return (b.amount ?? 0) - (a.amount ?? 0);
  });

  // Asked once, after every table has been read. Never throws.
  const coverage = await checkCoverage(state.rowsRead);

  return {
    findings: material,
    scannedRows: state.scannedRows,
    scannedTables: state.scannedTables,
    truncatedTables: state.truncatedTables,
    coverage,
    errors: state.errors,
    ranAt: new Date().toISOString(),
  };
}

export function severityCounts(findings: RiskFinding[]): Record<RiskSeverity, number> {
  const counts: Record<RiskSeverity, number> = { critical: 0, high: 0, medium: 0, low: 0 };
  for (const finding of findings) counts[finding.severity] += 1;
  return counts;
}

/** Findings per category, for the triage overview. */
export function categoryCounts(findings: RiskFinding[]): { label: string; value: number }[] {
  const counts = new Map<string, number>();
  for (const finding of findings) {
    counts.set(finding.category, (counts.get(finding.category) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}

export function findingsToCsv(findings: RiskFinding[]): string {
  const head = [
    'severity', 'category', 'source', 'rule', 'detail',
    'user_id', 'amount', 'unit', 'reference', 'created_at',
  ];
  const escape = (value: unknown) => `"${String(value ?? '').replace(/"/g, '""')}"`;

  return [
    head.join(','),
    ...findings.map((finding) =>
      [
        finding.severity, finding.category, finding.source, finding.rule, finding.detail,
        finding.userId, finding.amount, finding.unit, finding.reference, finding.createdAt,
      ]
        .map(escape)
        .join(',')
    ),
  ].join('\n');
}
