/**
 * Values the staking domain is allowed to hardcode.
 *
 * Note what is NOT here: APY. v2's SuperAdminDash carried an `APY_RATES` matrix
 * (token -> duration -> rate) baked into the bundle, and it disagreed with the
 * rates `process_staking_request` actually writes to `user_staking_pools`, so
 * the admin console and the member's own position showed different numbers for
 * the same stake. Every rate rendered by this domain is read from the database:
 * `user_staking_pools.dynamic_apy ?? apy_rate` for an open position,
 * `enhanced_staking_pools.apr_min/apr_max` for a pool template, and the
 * `calculate_dynamic_apy` RPC for a quote on an amount the user has typed.
 *
 * The lock periods below are not rates - they are the exact enum the
 * `submit-staking-request` edge function validates against. Sending anything
 * else is a guaranteed 400, so the picker mirrors the server's list.
 */

export const POOL_TYPES = ['str', 'ccos', 'domain'] as const;
export type PoolType = (typeof POOL_TYPES)[number];

export const POOL_TYPE_LABELS: Record<PoolType, string> = {
  str: 'STR',
  ccos: 'CCOS',
  domain: 'Domain',
};

/** Mirrors the `lock_period` enum in the submit-staking-request function. */
export const LOCK_PERIODS = ['3', '6', '9', '12', '24', '36', '48'] as const;
export type LockPeriod = (typeof LOCK_PERIODS)[number];

/** The same function rejects a 3-month domain stake, so the picker hides it. */
export function lockPeriodsFor(poolType: PoolType): readonly LockPeriod[] {
  return poolType === 'domain' ? LOCK_PERIODS.filter((p) => p !== '3') : LOCK_PERIODS;
}

/** Internal-wallet payment is only accepted for CCOS by the edge function. */
export function allowsInternalPayment(poolType: PoolType): boolean {
  return poolType === 'ccos';
}

export const TX_HASH_PATTERN = /^0x[a-fA-F0-9]{64}$/;

/**
 * Request statuses. `process_staking_request` writes 'approved' or 'declined';
 * rows arrive as 'pending'. v2 also had screens writing 'rejected' for the same
 * decision, which is why its request filters silently dropped rows - one
 * vocabulary is used here.
 */
export const REQUEST_STATUSES = ['pending', 'approved', 'declined'] as const;
export type RequestStatus = (typeof REQUEST_STATUSES)[number];

export const REQUEST_FILTERS = ['pending', 'approved', 'declined', 'all'] as const;
export type RequestFilter = (typeof REQUEST_FILTERS)[number];

export function isPoolType(value: string | null | undefined): value is PoolType {
  return POOL_TYPES.includes((value ?? '') as PoolType);
}

export function poolTypeLabel(value: string | null | undefined): string {
  const key = (value ?? '').toLowerCase();
  return isPoolType(key) ? POOL_TYPE_LABELS[key] : (value ?? '—').toUpperCase();
}
