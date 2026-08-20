import { useCallback, useSyncExternalStore } from 'react';

/**
 * SAFE MODE.
 *
 * Ported from v2 `src/lib/voucherSafeMode.ts`. While safe mode is armed — which
 * is the default, and the state any storage failure falls back to — no action
 * in this domain may push tokens or balances to a member account. Exposure can
 * be reviewed, risk can be scored, findings can be exported; nothing can be
 * credited.
 *
 * Two differences from v2:
 *
 *  - v2 armed safe mode over the voucher screens only. Here it governs every
 *    balance-affecting action in the domain, and each of those actions
 *    re-checks it inside the mutation rather than trusting a disabled button —
 *    a `disabled` attribute is a hint to a human, not a control.
 *  - v2 read the flag with `isSafeModeOn()` at render time and kept a copy in
 *    component state, so releasing safe mode in one tab left another tab's
 *    buttons enabled against a stale `true`. Here it is an external store, and
 *    every subscriber re-renders on change.
 */

const KEY = 'voucher_safe_mode';
const EVENT = 'voucher-safe-mode-changed';

/** The exact phrase an administrator must type to release safe mode. */
export const SAFE_MODE_RELEASE_PHRASE = 'PUSH TO BALANCES';

/** Armed unless explicitly turned off, including when storage is unavailable. */
export function isSafeModeOn(): boolean {
  try {
    return localStorage.getItem(KEY) !== 'off';
  } catch {
    return true;
  }
}

export function setSafeMode(on: boolean): void {
  try {
    localStorage.setItem(KEY, on ? 'on' : 'off');
  } catch {
    /* Storage unavailable. The getter falls back to armed, which is correct. */
  }
  window.dispatchEvent(new CustomEvent(EVENT, { detail: { on } }));
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener(EVENT, onChange);
  // `storage` fires for changes made in other tabs, which is where the stale
  // copy in v2 came from.
  window.addEventListener('storage', onChange);
  return () => {
    window.removeEventListener(EVENT, onChange);
    window.removeEventListener('storage', onChange);
  };
}

export interface SafeModeState {
  /** True when balance pushes are blocked. */
  armed: boolean;
  arm: () => void;
  /** Releases only when the phrase matches exactly. Returns whether it did. */
  release: (phrase: string) => boolean;
}

export function matchesReleasePhrase(phrase: string): boolean {
  return phrase.trim().toUpperCase() === SAFE_MODE_RELEASE_PHRASE;
}

export function useSafeMode(): SafeModeState {
  const armed = useSyncExternalStore(subscribe, isSafeModeOn, () => true);

  const arm = useCallback(() => setSafeMode(true), []);
  const release = useCallback((phrase: string) => {
    if (!matchesReleasePhrase(phrase)) return false;
    setSafeMode(false);
    return true;
  }, []);

  return { armed, arm, release };
}

/**
 * Guard called at the top of every balance-affecting mutation.
 *
 * Throws rather than returning a boolean so a caller cannot ignore it, and it
 * runs inside the mutation so it is checked at the moment of the write rather
 * than at the moment the button rendered.
 */
export function assertPushAllowed(confirmation: string): void {
  if (isSafeModeOn()) {
    throw new Error(
      'Safe mode is armed. Release it before any action that writes to member balances.'
    );
  }
  if (!matchesReleasePhrase(confirmation)) {
    throw new Error(`Type "${SAFE_MODE_RELEASE_PHRASE}" to confirm this action.`);
  }
}

/* ------------------------------ risk scoring ----------------------------- */

export interface RiskInput {
  voucherCount: number;
  uncreditedCount: number;
  voucherTokenTotal: number;
  usdValue: number;
  stakingTotal: number;
  fiatTotal: number;
  cryptoTotal: number;
  sharesTotal: number;
  safeUsdTotal: number;
  distinctEmails: number;
  distinctNames: number;
  duplicateHash: boolean;
  missingPaymentProof: boolean;
  accountAgeDays: number;
  profileApproved: boolean;
}

export type RiskLevel = 'critical' | 'high' | 'medium' | 'low';

export interface RiskResult {
  score: number;
  level: RiskLevel;
  reasons: string[];
}

/** Large-exposure thresholds (USD-equivalent unless stated). */
export const THRESHOLDS = {
  largeUsd: 25_000,
  hugeUsd: 100_000,
  largeTokens: 250_000,
  freshAccountDays: 14,
} as const;

/** Ported verbatim from v2 voucherSafeMode.ts — the scoring is unchanged. */
export function scoreRisk(i: RiskInput): RiskResult {
  const reasons: string[] = [];
  let score = 0;

  const totalExposure = i.usdValue + i.fiatTotal + i.cryptoTotal + i.safeUsdTotal;

  if (totalExposure >= THRESHOLDS.hugeUsd) {
    score += 45;
    reasons.push(`Very large exposure ($${Math.round(totalExposure).toLocaleString()})`);
  } else if (totalExposure >= THRESHOLDS.largeUsd) {
    score += 25;
    reasons.push(`Large exposure ($${Math.round(totalExposure).toLocaleString()})`);
  }

  if (i.voucherTokenTotal >= THRESHOLDS.largeTokens) {
    score += 20;
    reasons.push(`High voucher token volume (${Math.round(i.voucherTokenTotal).toLocaleString()})`);
  }

  if (i.stakingTotal + i.sharesTotal >= THRESHOLDS.largeTokens) {
    score += 10;
    reasons.push('Large staking / share position already credited');
  }

  if (i.voucherCount >= 5) {
    score += 15;
    reasons.push(`${i.voucherCount} voucher submissions from one account`);
  }

  if (i.duplicateHash) {
    score += 30;
    reasons.push('Duplicate payment hash / confirmation reused');
  }

  if (i.missingPaymentProof) {
    score += 20;
    reasons.push('Missing payment proof or transaction hash');
  }

  if (i.distinctEmails > 1 || i.distinctNames > 1) {
    score += 15;
    reasons.push('Inconsistent identity across submissions');
  }

  if (i.accountAgeDays >= 0 && i.accountAgeDays <= THRESHOLDS.freshAccountDays) {
    score += 10;
    reasons.push(`New account (${i.accountAgeDays}d) with pending value`);
  }

  if (!i.profileApproved) {
    score += 10;
    reasons.push('Profile not approved / KYC incomplete');
  }

  if (!reasons.length) reasons.push('No risk signals detected');

  const level: RiskLevel =
    score >= 70 ? 'critical' : score >= 45 ? 'high' : score >= 20 ? 'medium' : 'low';

  return { score: Math.min(score, 100), level, reasons };
}
