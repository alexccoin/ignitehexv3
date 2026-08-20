/**
 * Formatting helpers.
 *
 * Money is formatted from a number here because that is what the API returns,
 * but every amount is rendered through one of these so rounding and grouping
 * stay consistent across the app.
 */

const TOKEN_LABELS: Record<string, string> = {
  str: 'STR',
  ccos: 'CCOS',
  arss: 'ARSS',
  domain: 'DOMAIN',
  wstr: 'wSTR',
};

/**
 * The placeholder every helper here uses for "we do not have this figure".
 *
 * `shortDate`, `relativeTime`, `maskIban` and `byUnit` already answered this
 * way; `money` and `token` did not, and rendered a missing amount as 0. On a
 * money screen those are two different claims — "the server did not give us
 * this" and "you hold nothing" — and only one of them should ever be shown as
 * a balance. This is the same rule `fetchAvailable` and the price feeds follow
 * by returning null (see docs/FINDINGS.md F-035).
 */
const UNKNOWN = '—';

/** True for a figure we do not have. `0` is a figure we do have. */
const missing = (amount: number | null | undefined): boolean =>
  amount === null || amount === undefined || (typeof amount === 'number' && Number.isNaN(amount));

/** Fiat amount with currency, e.g. "€18,500.00". Null renders as "—", not €0.00. */
export function money(amount: number | null | undefined, currency = 'EUR'): string {
  if (missing(amount)) return UNKNOWN;
  const n = Number(amount);
  if (!Number.isFinite(n)) return UNKNOWN;
  return new Intl.NumberFormat('en-IE', {
    style: 'currency',
    currency,
    maximumFractionDigits: 2,
  }).format(n);
}

/** Token amount with symbol, e.g. "125,000 STR". Tokens are not currencies. */
export function token(amount: number | null | undefined, symbol: string): string {
  if (missing(amount)) return UNKNOWN;
  const n = Number(amount);
  if (!Number.isFinite(n)) return UNKNOWN;
  const label = TOKEN_LABELS[symbol?.toLowerCase()] ?? symbol?.toUpperCase() ?? '';
  const digits = n !== 0 && Math.abs(n) < 1 ? 6 : 2;
  return `${new Intl.NumberFormat('en-IE', { maximumFractionDigits: digits }).format(n)} ${label}`.trim();
}

/** Compact figure for tiles, e.g. "1.2M". */
export function compact(amount: number | null | undefined): string {
  return new Intl.NumberFormat('en-IE', { notation: 'compact', maximumFractionDigits: 1 }).format(
    Number(amount ?? 0)
  );
}

export function percent(value: number | null | undefined, digits = 2): string {
  return `${Number(value ?? 0).toFixed(digits)}%`;
}

export function shortDate(value: string | null | undefined): string {
  if (!value) return '—';
  return new Date(value).toLocaleDateString('en-IE', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
}

export function relativeTime(value: string | null | undefined): string {
  if (!value) return '—';
  const diff = Date.now() - new Date(value).getTime();
  const mins = Math.round(diff / 60000);
  if (Math.abs(mins) < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (Math.abs(hours) < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

/** Mask an IBAN for display, keeping enough to be recognisable. */
export function maskIban(iban: string | null | undefined): string {
  if (!iban) return '—';
  if (iban === '***ENCRYPTED***') return 'Encrypted';
  const clean = iban.replace(/\s+/g, '');
  if (clean.length <= 8) return clean;
  return `${clean.slice(0, 4)} •••• ${clean.slice(-4)}`;
}
