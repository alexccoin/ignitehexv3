import { supabase } from '@/lib/supabase';

/**
 * One chronological ledger built from every table that books a movement for
 * the member.
 *
 * v2 aggregated 21 tables through a `safe()` helper that swallowed the error
 * and returned `[]`, and it read all of them through `supabase as any`. Three
 * of those queries named columns that do not exist (`wallet_transactions.user_id`,
 * `crypto_wallets.wallet_address`), so they had been returning nothing for as
 * long as the code had shipped and nobody could tell, because a denied query
 * and an empty table produced the same blank screen.
 *
 * Here every source is typed against the real schema, and a source that fails
 * is reported by name in `unavailable` so the page can say "your fiat rail
 * could not be read" instead of quietly showing an incomplete statement.
 */

export type ActivityCategory = 'wallet' | 'transfer' | 'fiat' | 'swap' | 'staking';

export const CATEGORY_LABELS: Record<ActivityCategory, string> = {
  wallet: 'Wallet ledger',
  transfer: 'Peer transfers',
  fiat: 'Fiat rails',
  swap: 'Conversions',
  staking: 'Staking',
};

export interface ActivityEntry {
  id: string;
  category: ActivityCategory;
  /** Which system booked it, shown verbatim in the statement. */
  source: string;
  title: string;
  detail: string;
  amount: number;
  /** Token symbol or ISO currency code, always upper case. */
  currency: string;
  /** `neutral` is used for conversions, where value is not gained or lost. */
  direction: 'in' | 'out' | 'neutral';
  status: string;
  /** ISO timestamp. Entries without a usable timestamp are dropped. */
  date: string;
  hash: string | null;
}

export interface ActivityResult {
  entries: ActivityEntry[];
  /** Human names of the sources whose query failed. Never silently empty. */
  unavailable: string[];
}

/** Currencies that settle as cash rather than as a digital asset. */
const FIAT_CODES = new Set([
  'EUR', 'USD', 'GBP', 'CHF', 'RON', 'CZK', 'PLN', 'SEK', 'NOK', 'DKK',
  'HUF', 'CAD', 'AUD', 'JPY', 'TRY', 'AED',
]);

export const isFiatCode = (code: string): boolean => FIAT_CODES.has(code.toUpperCase());

const num = (v: unknown): number => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
};

const nice = (s: string | null | undefined): string =>
  (s ?? '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .trim();

const upper = (s: string | null | undefined, fallback: string): string =>
  s ? s.toUpperCase() : fallback;

/** Drop rows whose timestamp cannot be parsed rather than dating them to 1970. */
const iso = (value: string | null | undefined): string | null => {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
};

const LIMIT = 500;

export async function fetchActivity(userId: string): Promise<ActivityResult> {
  const either = (a: string, b: string) => `${a}.eq.${userId},${b}.eq.${userId}`;

  const [wallet, transfers, fiat, exchanges, arss, staking] = await Promise.all([
    supabase
      .from('wallet_transactions')
      .select(
        'id, token_type, amount, status, from_address, to_address, from_user_id, to_user_id, transaction_hash, created_at'
      )
      .or(either('from_user_id', 'to_user_id'))
      .order('created_at', { ascending: false })
      .limit(LIMIT),
    supabase
      .from('token_transfers')
      .select('id, token_type, amount, status, sender_id, recipient_id, notes, transaction_hash, created_at')
      .or(either('sender_id', 'recipient_id'))
      .order('created_at', { ascending: false })
      .limit(LIMIT),
    supabase
      .from('fiat_transactions')
      .select(
        'id, tx_id, currency, amount, fee, transfer_type, status, from_user_id, to_user_id, from_identifier, to_identifier, created_at'
      )
      .or(either('from_user_id', 'to_user_id'))
      .order('created_at', { ascending: false })
      .limit(LIMIT),
    supabase
      .from('currency_exchanges')
      .select(
        'id, from_currency, to_currency, from_amount, to_amount, exchange_rate, fee_amount, status, created_at'
      )
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(LIMIT),
    supabase
      .from('arss_transactions')
      .select('id, transaction_type, amount, currency, status, description, transaction_hash, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(LIMIT),
    supabase
      .from('staking_requests')
      .select('id, request_type, pool_type, amount, status, transaction_hash, created_at, requested_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(LIMIT),
  ]);

  const entries: ActivityEntry[] = [];
  const unavailable: string[] = [];

  const push = (entry: ActivityEntry | null) => {
    if (entry) entries.push(entry);
  };

  if (wallet.error) unavailable.push('Wallet ledger');
  for (const t of wallet.data ?? []) {
    const date = iso(t.created_at);
    if (!date) continue;
    const outbound = t.from_user_id === userId;
    push({
      id: `wt-${t.id}`,
      category: 'wallet',
      source: 'Wallet ledger',
      title: outbound ? `Sent ${upper(t.token_type, 'STR')}` : `Received ${upper(t.token_type, 'STR')}`,
      detail: outbound ? `To ${t.to_address}` : `From ${t.from_address}`,
      amount: num(t.amount),
      currency: upper(t.token_type, 'STR'),
      direction: outbound ? 'out' : 'in',
      status: t.status,
      date,
      hash: t.transaction_hash,
    });
  }

  if (transfers.error) unavailable.push('Peer transfers');
  for (const t of transfers.data ?? []) {
    const date = iso(t.created_at);
    if (!date) continue;
    const outbound = t.sender_id === userId;
    push({
      id: `tt-${t.id}`,
      category: 'transfer',
      source: 'Peer transfer',
      title: outbound ? `Sent ${upper(t.token_type, 'STR')}` : `Received ${upper(t.token_type, 'STR')}`,
      detail: t.notes ?? 'Token transfer between accounts',
      amount: num(t.amount),
      currency: upper(t.token_type, 'STR'),
      direction: outbound ? 'out' : 'in',
      status: t.status,
      date,
      hash: t.transaction_hash,
    });
  }

  if (fiat.error) unavailable.push('Fiat rails');
  for (const t of fiat.data ?? []) {
    const date = iso(t.created_at);
    if (!date) continue;
    const outbound = t.from_user_id === userId;
    const fee = num(t.fee);
    push({
      id: `ft-${t.id}`,
      category: 'fiat',
      source: 'Fiat rails',
      title: `${outbound ? 'Fiat sent' : 'Fiat received'} · ${nice(t.transfer_type)}`,
      detail: `${outbound ? `To ${t.to_identifier}` : `From ${t.from_identifier}`} · ${t.tx_id}${
        fee ? ` · fee ${fee}` : ''
      }`,
      amount: num(t.amount),
      currency: upper(t.currency, 'EUR'),
      direction: outbound ? 'out' : 'in',
      status: t.status,
      date,
      hash: null,
    });
  }

  if (exchanges.error) unavailable.push('Conversions');
  for (const e of exchanges.data ?? []) {
    const date = iso(e.created_at);
    if (!date) continue;
    const fee = num(e.fee_amount);
    push({
      id: `fx-${e.id}`,
      category: 'swap',
      source: 'Convert',
      title: `Swap ${upper(e.from_currency, '?')} → ${upper(e.to_currency, '?')}`,
      detail: `${num(e.from_amount)} ${upper(e.from_currency, '?')} at rate ${num(e.exchange_rate)}${
        fee ? ` · fee ${fee}` : ''
      }`,
      // A conversion neither adds to nor removes from the portfolio, so it is
      // never counted as a credit or a debit on a statement.
      amount: num(e.to_amount),
      currency: upper(e.to_currency, '?'),
      direction: 'neutral',
      status: e.status,
      date,
      hash: null,
    });
  }

  if (arss.error) unavailable.push('ARSS ledger');
  const OUTBOUND = /withdraw|send|debit|out|payment|spend|burn|sell|stake|purchase|buy/i;
  for (const t of arss.data ?? []) {
    const date = iso(t.created_at);
    if (!date) continue;
    push({
      id: `arss-${t.id}`,
      category: 'wallet',
      source: 'ARSS',
      title: `ARSS ${nice(t.transaction_type)}`,
      detail: t.description,
      amount: num(t.amount),
      currency: upper(t.currency, 'ARSS'),
      direction: OUTBOUND.test(t.transaction_type) ? 'out' : 'in',
      status: t.status,
      date,
      hash: t.transaction_hash,
    });
  }

  if (staking.error) unavailable.push('Staking');
  for (const s of staking.data ?? []) {
    const date = iso(s.created_at) ?? iso(s.requested_at);
    if (!date) continue;
    const isUnstake = /unstake|withdraw/i.test(s.request_type);
    push({
      id: `sr-${s.id}`,
      category: 'staking',
      source: 'Staking',
      title: `${nice(s.request_type) || 'Stake'} · ${nice(s.pool_type)}`,
      detail: `Staking request on the ${nice(s.pool_type)} pool`,
      amount: num(s.amount),
      currency: upper(s.pool_type, 'STR'),
      direction: isUnstake ? 'in' : 'out',
      status: s.status,
      date,
      hash: s.transaction_hash,
    });
  }

  entries.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

  return { entries, unavailable };
}
