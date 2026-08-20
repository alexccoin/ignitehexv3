/**
 * Fixed tables the bonuses domain reads from but never recomputes.
 *
 * The voucher package strings below are the most fragile piece of data in this
 * domain. `voucher_redemptions.package_type` is free text, and the server-side
 * correction jobs (`correct-precex-vouchers`, `correct-str-vouchers-targeted`)
 * find a row by matching that text against their own table byte for byte. v2
 * built the same strings by running the token amount through `toLocaleString()`,
 * which inserted thousands separators — so `Foundation ($2,500) ≈ 274,423.71 STR`
 * was written to the row while the job was looking for
 * `Foundation ($2500) ≈ 274423.71 STR`, and those vouchers fell out of every
 * repair sweep. v2 then had to carry a ~60-entry alias map of every
 * mis-formatted variant it had ever emitted.
 *
 * So these are written out verbatim as literals. They are never derived at
 * runtime, never passed through Intl, and never interpolated from a number.
 * `value` is what goes in the column, and nothing else is ever written there.
 */

export interface VoucherPackage {
  /** Written to voucher_redemptions.package_type EXACTLY as it appears here. */
  value: string;
  /** USD price of the tier. Display and ordering only. */
  usd: number;
  /** Tokens the tier is worth. An indication — the server decides the credit. */
  tokens: number;
}

/**
 * Pre-CEX STR listing vouchers, at a fixed 0.0015 USD per STR.
 *
 * The token counts are fixed allocations, not the rate multiplied out, which is
 * the other reason they are listed rather than computed.
 */
export const STR_VOUCHER_PACKAGES: readonly VoucherPackage[] = [
  { value: 'Launch Gate Voucher ($250) ≈ 166666 STR', usd: 250, tokens: 166666 },
  { value: 'Market Spark Voucher ($500) ≈ 333333 STR', usd: 500, tokens: 333333 },
  { value: 'Exchange Lift Voucher ($750) ≈ 500000 STR', usd: 750, tokens: 500000 },
  { value: 'Listing Prime Voucher ($1000) ≈ 666666 STR', usd: 1000, tokens: 666666 },
  { value: 'Access Surge Voucher ($1250) ≈ 833333 STR', usd: 1250, tokens: 833333 },
  { value: 'Exchange Anchor Voucher ($1500) ≈ 1000000 STR', usd: 1500, tokens: 1000000 },
  { value: 'Listing Force Voucher ($2000) ≈ 1333333 STR', usd: 2000, tokens: 1333333 },
  { value: 'Priority Wave Voucher ($2500) ≈ 1666666 STR', usd: 2500, tokens: 1666666 },
  { value: 'Market Rise Voucher ($5000) ≈ 3333333 STR', usd: 5000, tokens: 3333333 },
  { value: 'Exchange Elite Voucher ($10000) ≈ 6666666 STR', usd: 10000, tokens: 6666666 },
  { value: 'Listing Vanguard Voucher ($25000) ≈ 16666666 STR', usd: 25000, tokens: 16666666 },
  { value: 'Market Titan Voucher ($50000) ≈ 33333333 STR', usd: 50000, tokens: 33333333 },
  { value: 'Exchange Crown Voucher ($100000) ≈ 66666666 STR', usd: 100000, tokens: 66666666 },
];

/** CCOS vouchers at 10.13 USD per CCOS. */
export const CCOS_VOUCHER_PACKAGES: readonly VoucherPackage[] = [
  { value: 'Spark ($250) ≈ 24.68 CCOS', usd: 250, tokens: 24.68 },
  { value: 'Pulse ($300) ≈ 29.62 CCOS', usd: 300, tokens: 29.62 },
  { value: 'Signal ($350) ≈ 34.55 CCOS', usd: 350, tokens: 34.55 },
  { value: 'Node ($400) ≈ 39.49 CCOS', usd: 400, tokens: 39.49 },
  { value: 'Link ($450) ≈ 44.42 CCOS', usd: 450, tokens: 44.42 },
  { value: 'Core ($500) ≈ 49.36 CCOS', usd: 500, tokens: 49.36 },
  { value: 'Symmetry ($750) ≈ 74.04 CCOS', usd: 750, tokens: 74.04 },
  { value: 'Element ($1000) ≈ 98.72 CCOS', usd: 1000, tokens: 98.72 },
  { value: 'Vector ($1250) ≈ 123.40 CCOS', usd: 1250, tokens: 123.4 },
  { value: 'Catalyst ($1500) ≈ 148.08 CCOS', usd: 1500, tokens: 148.08 },
  { value: 'Apex ($2000) ≈ 197.43 CCOS', usd: 2000, tokens: 197.43 },
  { value: 'Foundation ($2500) ≈ 246.79 CCOS', usd: 2500, tokens: 246.79 },
  { value: 'Pioneer ($5000) ≈ 493.58 CCOS', usd: 5000, tokens: 493.58 },
  { value: "Innovator's ($10000) ≈ 987.17 CCOS", usd: 10000, tokens: 987.17 },
  { value: "Architect's ($25000) ≈ 2467.92 CCOS", usd: 25000, tokens: 2467.92 },
  { value: "Network Builder's ($50000) ≈ 4935.83 CCOS", usd: 50000, tokens: 4935.83 },
  { value: 'Quantum Core ($100000) ≈ 9871.67 CCOS', usd: 100000, tokens: 9871.67 },
];

/** ARSS vouchers at 0.00911 USD per ARSS. */
export const ARSS_VOUCHER_PACKAGES: readonly VoucherPackage[] = [
  { value: 'Foundation ($2500) ≈ 274423.71 ARSS', usd: 2500, tokens: 274423.71 },
  { value: 'Pioneer ($5000) ≈ 548847.42 ARSS', usd: 5000, tokens: 548847.42 },
  { value: "Innovator's ($10000) ≈ 1097694.84 ARSS", usd: 10000, tokens: 1097694.84 },
  { value: "Architect's ($25000) ≈ 2744237.10 ARSS", usd: 25000, tokens: 2744237.1 },
  { value: "Network Builder's ($50000) ≈ 5488474.20 ARSS", usd: 50000, tokens: 5488474.2 },
  { value: 'Quantum Core ($100000) ≈ 10976948.41 ARSS', usd: 100000, tokens: 10976948.41 },
];

export const VOUCHER_TOKEN_TYPES = ['str', 'ccos', 'arss'] as const;
export type VoucherTokenType = (typeof VOUCHER_TOKEN_TYPES)[number];

export const VOUCHER_PACKAGES: Record<VoucherTokenType, readonly VoucherPackage[]> = {
  str: STR_VOUCHER_PACKAGES,
  ccos: CCOS_VOUCHER_PACKAGES,
  arss: ARSS_VOUCHER_PACKAGES,
};

export const VOUCHER_TOKEN_LABELS: Record<VoucherTokenType, string> = {
  str: 'STR cryptocurrency',
  ccos: 'CCOS token',
  arss: 'ARSS token',
};

export type PaymentProof = 'hash' | 'confirmation' | 'none';

export const VOUCHER_PAYMENT_TYPES: readonly { value: string; label: string; requires: PaymentProof }[] = [
  { value: 'crypto', label: 'Cryptocurrency', requires: 'hash' },
  { value: 'card', label: 'Card payment', requires: 'confirmation' },
  { value: 'bank', label: 'Bank transfer', requires: 'none' },
];

/** Terms shown beside the STR ladder. Copy, not a rule the client enforces. */
export const STR_VOUCHER_TERMS: readonly string[] = [
  'Fixed rate: every tier is priced at 0.0015 USD per STR.',
  'Vesting: STR unlocks 30 days after the token is publicly accessible on the listing CEX, and only once the liquidity pool is confirmed active.',
  'No staking: this pre-listing sale generates no yield, rewards or APY.',
  'Redemption: after vesting, STR can be redeemed on the listing CEX or in HEX format through IgniteHeX.',
  'Governed by Ccoin Finance Corporate Structure CO., LTD, Phon Kham Village, Sikottabong District, Vientiane.',
];

/* -------------------------------------------------------------- airdrop */

export const AIRDROP_EVENT_TYPES: readonly { value: string; label: string }[] = [
  { value: 'sasp', label: 'SASP' },
  { value: 'sourceless', label: 'SourceLess' },
];

/** Statuses an admin can move a registration to that credit nothing. */
export const AIRDROP_NON_CREDITING_STATUSES = ['rejected', 'on_hold'] as const;

/* ------------------------------------------------------------ referrals */

/**
 * Headline referral rate, for copy only.
 *
 * What is actually paid is whatever the server wrote to
 * `referrals.reward_amount` and `seed_str_referrals.commission_amount`. This
 * string is never used to compute a figure presented as an amount: v2's
 * referral table back-calculated a "purchase value" by dividing each reward by
 * 0.125 and rendered the result as if it were the recorded purchase.
 */
export const REFERRAL_RATE_COPY = '12.5% in wSTR on every converted referral';

/** Networks commission can be paid on. Stored verbatim on the affiliate row. */
export const PAYOUT_NETWORKS: readonly string[] = [
  'ERC20',
  'BEP20',
  'Polygon',
  'Arbitrum',
  'Optimism',
];

/** Commission is paid to an EVM address, so it has to look like one. */
export const EVM_ADDRESS = /^0x[a-fA-F0-9]{40}$/;

export const REFERRAL_STEPS: readonly { title: string; body: string }[] = [
  { title: 'Share your link', body: 'Send your referral link to people you know.' },
  { title: 'They subscribe', body: 'They open an account and complete a purchase through your link.' },
  {
    title: 'The server credits you',
    body: 'Commission is calculated and released server-side once the purchase settles.',
  },
];

/* -------------------------------------------------------------- display */

/** Where a reward can come from, in the fixed order the charts use. */
export const REWARD_SOURCES = ['voucher', 'airdrop', 'referral', 'affiliate', 'starw'] as const;
export type RewardSource = (typeof REWARD_SOURCES)[number];

export const REWARD_SOURCE_LABELS: Record<RewardSource, string> = {
  voucher: 'Vouchers',
  airdrop: 'Airdrop',
  referral: 'Referrals',
  affiliate: 'Affiliate',
  starw: 'StarW nodes',
};
