/**
 * Investment offering data.
 *
 * These are the terms of live offerings, lifted from v2 so the numbers on
 * screen do not drift. They live in one module rather than being redeclared
 * per page — v2 had the seed tier table copied into two files and the seed
 * share price stated as $5.00 in one screen and $9.00 in another, so two
 * pages quoted different prices for the same instrument.
 *
 * Deliberately absent: treasury deposit addresses. v2 hardcoded BTC/EVM
 * addresses into five pages, in three different sets that did not agree with
 * one another. A payment address belongs with the payment intent the server
 * issues, so that rotating it does not need a redeploy and a tampered bundle
 * cannot quietly redirect funds.
 */

/** STR reference price used to convert a USD commitment into STR units. */
export const STR_REFERENCE_PRICE = 0.0015;

/** Share price for the seed round, in USD. */
export const SEED_SHARE_PRICE = 5;

export interface InvestmentTier {
  value: string;
  label: string;
  minUsd: number;
  /** null means uncapped. v2 used `Infinity`, which does not survive JSON. */
  maxUsd: number | null;
  description: string;
}

export const SEED_TIERS: readonly InvestmentTier[] = [
  {
    value: 'retail_tier1',
    label: 'Retail Tier 1',
    minUsd: 10_000,
    maxUsd: 50_000,
    description: '10,000 - 50,000 USD equivalent',
  },
  {
    value: 'retail_tier2',
    label: 'Retail Tier 2',
    minUsd: 50_001,
    maxUsd: 500_000,
    description: 'Up to 10 tickets of 50,000 USD',
  },
  {
    value: 'professional',
    label: 'Professional investor',
    minUsd: 0,
    maxUsd: null,
    description: 'No cap - requires certification',
  },
];

export const SEED_LOCK_MONTHS = 12;
export const SEED_MIN_USD = 10_000;

/** Seed round stages. Stage 2 carries shares only, with no STR entitlement. */
export const SEED_STAGES = [
  {
    stage: 1,
    window: '07 Apr 2026 - 15 Apr 2026 (24:00 CET)',
    priceUsd: SEED_SHARE_PRICE,
    shares: 100_000,
    strPerShare: 3333.33,
    note: 'Shares + STR tokens',
  },
  {
    stage: 2,
    window: '16 Apr 2026 - 21 Apr 2026',
    priceUsd: SEED_SHARE_PRICE,
    shares: 100_000,
    strPerShare: 0,
    note: 'Shares only',
  },
];

/** Private STR IPO sale. Price is a function of the phase. */
export const IPO_PHASES = [
  { phase: 'phase1', label: 'Phase 1 - IPO price', pricePerStr: 0.005, endsAt: '2026-03-15T23:59:59Z' },
  { phase: 'phase2', label: 'Phase 2', pricePerStr: 0.01, endsAt: '2026-04-15T23:59:59Z' },
];

export const IPO_MIN_USD = 2_500;
export const IPO_MAX_USD = 250_000;

/** Pre-listing voucher ladder. Fixed packages, no free-form amount. */
export interface PrelistingVoucher {
  usd: number;
  str: number;
  name: string;
}

export const PRELISTING_VOUCHERS: readonly PrelistingVoucher[] = [
  { usd: 250, str: 166_666, name: 'Launch Gate' },
  { usd: 500, str: 333_333, name: 'Market Spark' },
  { usd: 750, str: 500_000, name: 'Exchange Lift' },
  { usd: 1_000, str: 666_666, name: 'Listing Prime' },
  { usd: 1_250, str: 833_333, name: 'Access Surge' },
  { usd: 1_500, str: 1_000_000, name: 'Exchange Anchor' },
  { usd: 2_000, str: 1_333_333, name: 'Listing Force' },
  { usd: 2_500, str: 1_666_666, name: 'Priority Wave' },
  { usd: 5_000, str: 3_333_333, name: 'Market Rise' },
  { usd: 10_000, str: 6_666_666, name: 'Exchange Elite' },
  { usd: 25_000, str: 16_666_666, name: 'Listing Vanguard' },
  { usd: 50_000, str: 33_333_333, name: 'Market Titan' },
  { usd: 100_000, str: 66_666_666, name: 'Exchange Crown' },
];

export const PRELISTING_PRICE_PER_STR = 0.0015;

/** Private digital shares, issued as wNFT certificates. */
export const DIGITAL_SHARE_PRICE = 9;
export const DIGITAL_SHARES_MIN = Math.ceil(2_500 / DIGITAL_SHARE_PRICE);
export const DIGITAL_SHARES_MAX = 100_000;

/** SAFE subscription. */
export const SAFE_PRICE_PER_SHARE = 20;
export const SAFE_MIN_SHARES = 50;
export const SAFE_MAX_SHARES = 25_000;

export const SAFE_BONUS_TIERS = [
  { threshold: 25_000, bonusPct: 12.5 },
  { threshold: 10_000, bonusPct: 10 },
  { threshold: 5_000, bonusPct: 5 },
  { threshold: 2_500, bonusPct: 2.5 },
];

export const SAFE_SUBSCRIPTION_RANGE = `${SAFE_MIN_SHARES.toLocaleString('en-IE')} - ${SAFE_MAX_SHARES.toLocaleString('en-IE')} shares`;

export const SAFE_TERMS = {
  issuer: 'SourceLess Inc.',
  instrument: 'SAFE (Simple Agreement for Future Equity)',
  eligibility: 'Accredited / qualified investors',
  conversionTrigger: 'Next priced equity round or liquidity event',
  interest: 'None',
  maturity: 'None',
  offerWindow: '08 Jul 2026 - 22 Jul 2026 (24:00 UTC)',
  referencePrice: 'USD 20.00 per share (indicative subscription unit)',
};

/* ------------------------------------------------------------ IPO listing */

/** Price at which existing holdings may be listed for the IPO, in USD. */
export const IPO_LISTING_PRICE_PER_SHARE = 91.3;

export const IPO_LISTING_SHARE_TYPES = [
  { value: 'seed_private_sale', label: 'STR Seed Private Sale' },
  { value: 'ssi', label: 'SSI' },
  { value: 'pre_ipo', label: 'Pre-IPO' },
];

export const IPO_LISTING_CURRENCIES = ['USD', 'EUR'];

/* ----------------------------------------------------------- founder pool */

/**
 * Pool metadata. `symbol` is the ticker everything else prices against — v2
 * derived it as `pool_type.toUpperCase()`, which turned 'ethereum' into
 * 'ETHEREUM', never matched the 'ETH' price key, and so valued every ETH pool
 * at zero. The mapping is explicit here for exactly that reason.
 */
export const FOUNDER_POOL_META: Record<string, { name: string; symbol: string }> = {
  btc: { name: 'Bitcoin', symbol: 'BTC' },
  ethereum: { name: 'Ethereum', symbol: 'ETH' },
  str: { name: 'SourceLess', symbol: 'STR' },
  ccos: { name: 'CCoin', symbol: 'CCOS' },
  arss: { name: 'ARSS', symbol: 'ARSS' },
};

export function founderPoolMeta(poolType: string): { name: string; symbol: string } {
  return (
    FOUNDER_POOL_META[poolType] ?? { name: poolType.toUpperCase(), symbol: poolType.toUpperCase() }
  );
}

/**
 * Founder positions are numbered slots, each capped in USD.
 *
 * The per-position minimum is not repeated here: it lives on the row as
 * `min_deposit_usd`, and v2 kept a second copy in the client that disagreed
 * with it — the UI advertised a $10,000 minimum while the check enforced
 * $100,000, so the form rejected deposits it had just invited.
 */
export const FOUNDER_POSITION_SLOTS = 13;
export const FOUNDER_POSITION_MAX_USD = 1_000_000;
export const FOUNDER_LOCK_DAYS = 90;
/** Declared CCOS mint band, in percent. Shown for reference; the server decides. */
export const CCOS_MINT_BAND = { min: 12.5, max: 17.5 };

/* -------------------------------------------------------------- vouchers */

/** Token families a voucher can be redeemed into. */
export const VOUCHER_TOKEN_TYPES = ['str', 'ccos', 'arss'];

/** How the voucher was paid for. Drives which proof field is required. */
export const VOUCHER_PAYMENT_TYPES = [
  { value: 'crypto', label: 'Crypto transfer', requires: 'hash' as const },
  { value: 'card', label: 'Card payment', requires: 'confirmation' as const },
  { value: 'bank', label: 'Bank transfer', requires: 'confirmation' as const },
];

/**
 * Voucher packages, per token family.
 *
 * Package labels are stored on the row as free text and later matched against
 * this table by the correction jobs, so a label must never be reformatted —
 * in particular it must never contain a thousands separator, which is what
 * `toLocaleString()` produced in v2 and what broke the match.
 */
export interface VoucherPackage {
  /** The exact string written to voucher_redemptions.package_type. */
  value: string;
  label: string;
  usd: number;
  tokens: number;
}

export const CCOS_PRICE_PER_TOKEN = 10.13;
export const ARSS_PRICE_PER_TOKEN = 0.00911;

const BASE_PACKAGE_TIERS = [
  { name: 'Foundation', usd: 2_500 },
  { name: 'Pioneer', usd: 5_000 },
  { name: "Innovator's", usd: 10_000 },
  { name: "Architect's", usd: 25_000 },
  { name: "Network Builder's", usd: 50_000 },
  { name: 'Quantum Core', usd: 100_000 },
];

function derivedPackages(rate: number, symbol: string): VoucherPackage[] {
  return BASE_PACKAGE_TIERS.map(({ name, usd }) => {
    const tokens = usd / rate;
    return {
      value: `${name} ($${usd})`,
      label: `${name} - $${usd.toLocaleString('en-IE')} (${tokens.toFixed(2)} ${symbol})`,
      usd,
      tokens,
    };
  });
}

/** Pre-CEX STR vouchers are fixed-token, not rate-derived. */
const STR_VOUCHER_PACKAGES: VoucherPackage[] = PRELISTING_VOUCHERS.map((v) => ({
  value: `${v.name} Voucher ($${v.usd})`,
  label: `${v.name} - $${v.usd.toLocaleString('en-IE')} (${v.str.toLocaleString('en-IE')} STR)`,
  usd: v.usd,
  tokens: v.str,
}));

export const VOUCHER_PACKAGES: Record<string, VoucherPackage[]> = {
  str: STR_VOUCHER_PACKAGES,
  ccos: derivedPackages(CCOS_PRICE_PER_TOKEN, 'CCOS'),
  arss: derivedPackages(ARSS_PRICE_PER_TOKEN, 'ARSS'),
};

/* --------------------------------------------------------------- airdrop */

export const AIRDROP_EVENT_TYPES = [
  { value: 'sasp', label: 'SASP' },
  { value: 'sourceless', label: 'SourceLess' },
];

/** Only offered for the 'sourceless' event. */
export const AIRDROP_VOUCHER_TYPES = [
  'str-2500',
  'str-5000',
  'str-10000',
  'str-25000',
  'ccos-2500',
  'ccos-5000',
  'ccos-10000',
  'ccos-25000',
];

/* ------------------------------------------------------------- offerings */

export type OfferingId =
  | 'seed_str'
  | 'private_seed_str'
  | 'str_ipo'
  | 'str_prelisting'
  | 'digital_shares'
  | 'safe'
  | 'starw'
  | 'airdrop';

export interface Offering {
  id: OfferingId;
  name: string;
  instrument: string;
  price: string;
  terms: string;
  /** Where a member goes to act, or null when nothing here is actionable. */
  href: string | null;
  /**
   * Set when the offering cannot be subscribed to from the browser. The text
   * is shown to the member; the server function each one needs is named in a
   * TODO beside the disabled control.
   */
  blocked: string | null;
  /** Needs an entitlement the client cannot verify on its own. */
  restricted: boolean;
}

export const OFFERINGS: readonly Offering[] = [
  {
    id: 'seed_str',
    name: 'STR seed round',
    instrument: 'Shares + STR tokens',
    price: '$5.00 per share, STR at $0.0015',
    terms: `${SEED_LOCK_MONTHS}-month lock on STR, minimum $${SEED_MIN_USD.toLocaleString('en-IE')}`,
    href: '/investments/applications',
    blocked:
      'Applications are recorded server-side so the source address and audit entry cannot be forged.',
    restricted: false,
  },
  {
    id: 'private_seed_str',
    name: 'Private STR seed round',
    instrument: 'Shares + STR tokens',
    price: '$5.00 per share, STR at $0.0015',
    terms: `${SEED_LOCK_MONTHS}-month lock, minimum $${SEED_MIN_USD.toLocaleString('en-IE')}`,
    href: '/investments/applications',
    blocked:
      'Applications are recorded server-side so the source address and audit entry cannot be forged.',
    restricted: true,
  },
  {
    id: 'str_ipo',
    name: 'STR IPO sale',
    instrument: 'STR tokens',
    price: 'Phase 1 $0.005, Phase 2 $0.010',
    terms: `1-year vesting, $${IPO_MIN_USD.toLocaleString('en-IE')} - $${IPO_MAX_USD.toLocaleString('en-IE')}`,
    href: null,
    blocked:
      'Orders are created by the server, so the payment address and quoted rate are never client-supplied.',
    restricted: true,
  },
  {
    id: 'str_prelisting',
    name: 'STR pre-listing vouchers',
    instrument: 'STR tokens',
    price: `$${PRELISTING_PRICE_PER_STR} per STR`,
    terms: 'Vests 30 days after CEX listing, 13 fixed packages',
    href: null,
    blocked:
      'Orders are created by the server, so the payment address and quoted rate are never client-supplied.',
    restricted: true,
  },
  {
    id: 'digital_shares',
    name: 'Digital shares (wNFT)',
    instrument: 'SourceLess Inc. digital shares',
    price: `$${DIGITAL_SHARE_PRICE}.00 per share`,
    terms: `${DIGITAL_SHARES_MIN.toLocaleString('en-IE')} - ${DIGITAL_SHARES_MAX.toLocaleString('en-IE')} shares, no lock`,
    href: null,
    blocked:
      'Orders are created by the server, so the payment address and quoted rate are never client-supplied.',
    restricted: true,
  },
  {
    id: 'safe',
    name: 'SSI SAFE subscription',
    instrument: SAFE_TERMS.instrument,
    price: `$${SAFE_PRICE_PER_SHARE}.00 per share`,
    terms: `${SAFE_SUBSCRIPTION_RANGE}, volume bonus up to ${SAFE_BONUS_TIERS[0].bonusPct}%`,
    href: null,
    blocked:
      'Subscriptions need the on-chain payment confirmed server-side; a transaction hash typed into the browser proves nothing.',
    restricted: true,
  },
  {
    id: 'starw',
    name: 'StarW nodes',
    instrument: 'Validator node licences',
    price: 'Stage-priced',
    terms: 'wSTR rewards accrue per node',
    href: '/investments/positions',
    blocked: 'Node purchases settle server-side before a node is assigned.',
    restricted: false,
  },
  {
    id: 'airdrop',
    name: 'Token airdrop',
    instrument: 'STR / CCOS tokens',
    price: 'Free',
    terms: 'One registration per member, credited after review',
    href: '/investments/rewards',
    blocked: null,
    restricted: false,
  },
];
