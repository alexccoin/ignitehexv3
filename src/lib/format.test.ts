import { describe, it, expect } from 'vitest';
import { money, token, compact, percent, shortDate, relativeTime, maskIban } from './format';

/**
 * Formatting.
 *
 * Two properties here are not cosmetic:
 *
 *  - `maskIban` must never emit a full IBAN. It is the only thing standing
 *    between a bank account number and a screen, a screenshot, or a support
 *    transcript.
 *  - A missing amount must not render as 0. On a balance screen "we do not have
 *    this figure" and "you hold nothing" are different claims, and 0 is a
 *    perfectly plausible real balance — the same reason `fetchAvailable` and
 *    both price feeds return null rather than a number.
 */

// U+00A0 and U+202F written as escapes, not as themselves: Intl emits both,
// and a literal one in the source is invisible in a diff and indistinguishable
// from a plain space to every reader and reviewer.
const flat = (s: string) => s.replace(/[\u00A0\u202F]/g, ' ');

describe('money', () => {
  it('formats a fiat amount with its currency symbol', () => {
    expect(flat(money(18_500, 'EUR'))).toBe('€18,500.00');
    // en-IE disambiguates the dollar as "US$", which is what /guardian/reserves
    // prints. Asserting the exact string keeps that from silently becoming a
    // bare "$" that could be read as any of six dollars.
    expect(flat(money(1_234.5, 'USD'))).toBe('US$1,234.50');
  });

  it('defaults to EUR', () => {
    expect(flat(money(1))).toBe('€1.00');
  });

  it('renders 0 as 0 — a real zero balance is a fact worth stating', () => {
    expect(flat(money(0, 'EUR'))).toBe('€0.00');
  });

  it('does NOT render null or undefined as 0', () => {
    // The defect this asserts against: a fiat wallet whose balance did not come
    // back reads "€0.00", indistinguishable from an empty wallet. The member
    // cannot tell a failed read from a spent account.
    expect(money(null, 'EUR')).toBe('—');
    expect(money(undefined, 'EUR')).toBe('—');
    expect(money(null)).not.toContain('0');
    expect(money(undefined)).not.toContain('0');
  });

  it('does not render NaN or Infinity as a number', () => {
    expect(money(Number.NaN, 'EUR')).toBe('—');
    expect(money(Number.POSITIVE_INFINITY, 'EUR')).toBe('—');
  });

  it('keeps a negative amount negative', () => {
    // A debit rendered without its sign is a credit.
    expect(flat(money(-250, 'EUR'))).toContain('250.00');
    expect(money(-250, 'EUR')).toMatch(/-/);
  });

  it('rounds to 2 decimals rather than truncating', () => {
    expect(flat(money(1.005, 'EUR'))).toBe('€1.01');
    expect(flat(money(0.994, 'EUR'))).toBe('€0.99');
  });
});

describe('token', () => {
  it('formats a token amount with its symbol, uppercased from the pool_type', () => {
    expect(token(125_000, 'str')).toBe(`125,000 STR`);
    expect(token(23_542, 'ccos')).toBe('23,542 CCOS');
    expect(token(1, 'wstr')).toBe('1 wSTR');
  });

  it('never prints a currency symbol in front of a token', () => {
    // Tokens are not currencies. v2 rendered "$125,000" for a STR balance,
    // which reads as a dollar figure and is off by whatever STR is worth.
    const out = token(125_000, 'str');
    expect(out).not.toContain('$');
    expect(out).not.toContain('€');
  });

  it('keeps six decimals for sub-unit amounts, so a small holding is not shown as 0', () => {
    expect(token(0.000123, 'btc')).toBe('0.000123 BTC');
    expect(token(0.000123, 'btc')).not.toBe('0 BTC');
  });

  it('renders 0 as 0', () => {
    expect(token(0, 'str')).toBe('0 STR');
  });

  it('does NOT render null or undefined as 0', () => {
    expect(token(null, 'str')).toBe('—');
    expect(token(undefined, 'str')).toBe('—');
  });

  it('does not render NaN as a number', () => {
    expect(token(Number.NaN, 'str')).toBe('—');
  });

  it('falls back to the raw symbol for a token it has no label for', () => {
    expect(token(5, 'arx')).toBe('5 ARX');
  });

  it('does not emit a stray trailing space when the symbol is empty', () => {
    expect(token(5, '')).toBe('5');
  });
});

describe('maskIban', () => {
  const IBAN = 'IE29AIBK93115212345678';

  it('never emits the full IBAN', () => {
    const out = maskIban(IBAN);
    expect(out).not.toContain(IBAN);
    expect(out).not.toBe(IBAN);
  });

  it('never emits the full IBAN when it arrives with spaces in it', () => {
    // The formatted form is how a bank prints it and how a user pastes it.
    // Stripping the spaces before masking is what makes this safe; comparing
    // the masked output against the *cleaned* input is what proves it.
    const spaced = 'IE29 AIBK 9311 5212 3456 78';
    const out = maskIban(spaced);
    expect(out).not.toContain(spaced.replace(/\s+/g, ''));
    expect(out).toBe('IE29 •••• 5678');
  });

  it('exposes at most 8 of the IBAN\'s characters', () => {
    // The middle of an Irish IBAN is the sort code and account number. Four at
    // each end identifies the account to its owner without reconstructing it.
    const revealed = maskIban(IBAN).replace(/[^A-Z0-9]/gi, '');
    expect(revealed.length).toBeLessThanOrEqual(8);
    expect(revealed).toBe('IE295678');
  });

  it('leaks nothing for a range of real-shaped IBANs', () => {
    const ibans = [
      'IE29AIBK93115212345678',
      'DE89370400440532013000',
      'GB29NWBK60161331926819',
      'FR1420041010050500013M02606',
      'NL91ABNA0417164300',
      'ES9121000418450200051332',
    ];
    for (const iban of ibans) {
      const out = maskIban(iban);
      expect(out, iban).not.toContain(iban);
      // The account-identifying middle must be gone.
      const middle = iban.slice(4, -4);
      expect(out, `${iban} leaked its middle`).not.toContain(middle);
      expect(out).toContain('••••');
    }
  });

  it('returns the value unchanged only when it is too short to be an IBAN', () => {
    // A shorter-than-9 value is not a maskable IBAN — masking it to 8 revealed
    // characters would reveal all of it anyway, so it is passed through and the
    // caller is responsible for not putting a secret there. The shortest real
    // IBAN is 15 characters (Norway), so nothing real reaches this branch.
    expect(maskIban('12345678')).toBe('12345678');
    expect('12345678'.length).toBeLessThan(15);
  });

  it('reports an absent IBAN as an em dash, not as an empty box', () => {
    expect(maskIban(null)).toBe('—');
    expect(maskIban(undefined)).toBe('—');
    expect(maskIban('')).toBe('—');
  });

  it('says "Encrypted" rather than masking the sentinel', () => {
    // iban_accounts stores '***ENCRYPTED***' when is_data_encrypted is set.
    // Masking it would produce "***E •••• ED**", which reads like a real IBAN.
    expect(maskIban('***ENCRYPTED***')).toBe('Encrypted');
  });
});

describe('compact, percent, dates', () => {
  it('compacts large figures for tiles', () => {
    expect(compact(1_200_000)).toBe('1.2M');
    expect(compact(2_546_068_134)).toBe('2.5B');
  });

  it('percent keeps the requested precision', () => {
    expect(percent(12.5)).toBe('12.50%');
    expect(percent(12.5, 0)).toBe('13%');
  });

  it('dates render an em dash for null rather than "Invalid Date"', () => {
    expect(shortDate(null)).toBe('—');
    expect(relativeTime(null)).toBe('—');
    expect(relativeTime(undefined)).toBe('—');
  });

  it('relativeTime steps through minutes, hours and days', () => {
    const ago = (ms: number) => new Date(Date.now() - ms).toISOString();
    expect(relativeTime(ago(5 * 60_000))).toBe('5m ago');
    expect(relativeTime(ago(3 * 3_600_000))).toBe('3h ago');
    expect(relativeTime(ago(4 * 86_400_000))).toBe('4d ago');
  });
});
