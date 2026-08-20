import { useCallback, useEffect, useReducer, useSyncExternalStore } from 'react';

/**
 * SAFE MODE.
 *
 * Nothing in this domain may push tokens or balances onto a member's account
 * while safe mode is engaged, and safe mode is engaged by default. An admin can
 * read the queues, inspect the audit trail, score risk and export all day; the
 * moment an action would credit something, it is refused until the phrase below
 * has been typed out in full.
 *
 * This is v2's `voucherSafeMode.ts` idea, with its two weaknesses fixed:
 *
 *  - v2 stored the release in `localStorage`, so once an admin had released it
 *    the crediting paths stayed open on that machine forever — across sessions,
 *    across days, and for anyone else who used the browser. Here the release
 *    lives in `sessionStorage` and additionally expires after fifteen minutes,
 *    so the default state reasserts itself without anybody remembering to.
 *  - v2 only used the flag to grey out buttons. A disabled button is a hint,
 *    not a control: the mutation underneath still ran if anything else called
 *    it. Here `assertCreditingAllowed()` is called inside the mutation itself,
 *    so the block holds whether or not the UI asked politely.
 *
 * None of this is a security boundary — the browser owns its own storage. The
 * boundary is the database's own authorisation inside the RPCs. This is a
 * guard against the far likelier failure: an admin clicking approve on the
 * wrong row, or a bulk sweep fired at production by reflex.
 */

export const SAFE_MODE_RELEASE_PHRASE = 'PUSH TO BALANCES';

/** How long a release lasts before safe mode re-engages on its own. */
export const SAFE_MODE_RELEASE_WINDOW_MS = 15 * 60 * 1000;

const KEY = 'bonuses.safe_mode_release_until';
const EVENT = 'bonuses:safe-mode-changed';

/** Epoch ms until which crediting is permitted; 0 means blocked. */
function readReleasedUntil(): number {
  try {
    const raw = window.sessionStorage.getItem(KEY);
    if (!raw) return 0;
    const until = Number(raw);
    if (!Number.isFinite(until) || until <= Date.now()) return 0;
    return until;
  } catch {
    // Storage unavailable is not permission. Fail closed.
    return 0;
  }
}

function write(until: number): void {
  try {
    if (until > 0) window.sessionStorage.setItem(KEY, String(until));
    else window.sessionStorage.removeItem(KEY);
  } catch {
    /* storage unavailable; the in-memory default is already "blocked" */
  }
  window.dispatchEvent(new CustomEvent(EVENT));
}

/** True whenever a crediting action must be refused. */
export function isCreditingBlocked(): boolean {
  return readReleasedUntil() === 0;
}

/**
 * Open the crediting window.
 *
 * Returns false — and changes nothing — unless the phrase matches exactly.
 * Deliberately case-sensitive and whitespace-trimmed only at the ends: the
 * point of the phrase is that it cannot be typed by accident.
 */
export function releaseSafeMode(phrase: string): boolean {
  if (phrase.trim() !== SAFE_MODE_RELEASE_PHRASE) return false;
  write(Date.now() + SAFE_MODE_RELEASE_WINDOW_MS);
  return true;
}

/** Close the window immediately. */
export function engageSafeMode(): void {
  write(0);
}

/**
 * Refuse a crediting action while safe mode holds.
 *
 * Called from inside the mutation, not from the click handler, so that the
 * block cannot be bypassed by a caller that forgot to check.
 */
export function assertCreditingAllowed(action: string): void {
  if (isCreditingBlocked()) {
    throw new Error(
      `Safe mode is on, so "${action}" was not performed. Type "${SAFE_MODE_RELEASE_PHRASE}" to release the crediting window first.`
    );
  }
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener(EVENT, onChange);
  window.addEventListener('storage', onChange);
  // The release expires on a timer rather than on an event, so the UI has to
  // notice the clock passing it. One tick a second is enough for a countdown.
  const timer = window.setInterval(onChange, 1_000);
  return () => {
    window.removeEventListener(EVENT, onChange);
    window.removeEventListener('storage', onChange);
    window.clearInterval(timer);
  };
}

export interface SafeModeState {
  /** True when crediting is refused. The default, and the state after expiry. */
  blocked: boolean;
  /** Epoch ms the current release runs out; 0 when blocked. */
  releasedUntil: number;
  /** Whole seconds left in the window; 0 when blocked. */
  secondsRemaining: number;
  /** Attempt a release. False means the phrase did not match. */
  release: (phrase: string) => boolean;
  engage: () => void;
}

export function useSafeMode(): SafeModeState {
  const releasedUntil = useSyncExternalStore(subscribe, readReleasedUntil, () => 0);

  // `readReleasedUntil` returns the same number for the whole window, so the
  // store alone never re-renders while the window is open — the countdown would
  // freeze on the second it was released. This ticks once a second, but only
  // while there is something to count down.
  const [, tick] = useReducer((n: number) => n + 1, 0);
  useEffect(() => {
    if (releasedUntil === 0) return;
    const timer = window.setInterval(tick, 1_000);
    return () => window.clearInterval(timer);
  }, [releasedUntil]);

  const release = useCallback((phrase: string) => releaseSafeMode(phrase), []);
  const engage = useCallback(() => engageSafeMode(), []);

  return {
    blocked: releasedUntil === 0,
    releasedUntil,
    secondsRemaining: releasedUntil === 0 ? 0 : Math.max(0, Math.ceil((releasedUntil - Date.now()) / 1000)),
    release,
    engage,
  };
}

/**
 * Re-engage safe mode when the admin screen unmounts.
 *
 * Navigating away from the review queue with the window still open is how an
 * accidental credit happens twenty minutes later on a different screen.
 */
export function useSafeModeAutoEngage(): void {
  useEffect(() => () => engageSafeMode(), []);
}
