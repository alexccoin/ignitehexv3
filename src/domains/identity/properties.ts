import { Banknote, Coins, Globe, Signal, type LucideIcon } from 'lucide-react';

/**
 * The sibling properties one IgniteHeX identity can reach.
 *
 * `v2_service_connections.service` is a text column with a CHECK constraint
 * listing six values. Four of them name a property a member can actually meet:
 * str.domains, strdome.com, ccoin.finance and CCoin Bank. The remaining two,
 * `offshore_banking` and `onshore_banking`, are booking modes inside CCoin Bank
 * rather than separate properties — see UNSURFACED_SERVICES below. They are
 * deliberately not given cards, because a card is a promise that there is
 * something on the other end.
 */
export type ServiceKey = 'str_domains' | 'str_dome' | 'ccoin_finance' | 'ccoin_bank';

/**
 * How much of this property exists on this deployment.
 *
 * This is the field that stops the page inventing state. v2's WalletModal drew
 * a "Connected" pill from a component prop, so a member saw a green pill for an
 * integration that had never been built. Here the pill comes from the row and
 * this field says, next to it, what the row is actually evidence of.
 *
 *  - `linked`   — tables on this database back the property, and a member's
 *                 activity there is visible from here.
 *  - `record_only` — the link record can be held, but nothing on this
 *                 deployment can confirm it against the property.
 */
export type IntegrationLevel = 'linked' | 'record_only';

export interface Property {
  key: ServiceKey;
  name: string;
  host: string;
  icon: LucideIcon;
  /** One line on what the property is. */
  summary: string;
  /** What connecting actually gives the member. Rendered verbatim. */
  grants: string[];
  integration: IntegrationLevel;
  /** The tables or screens that justify `integration`. Rendered on the card. */
  evidence: string;
  /**
   * The `metadata` key this property keeps its own reference under, so
   * property-specific detail stays in jsonb rather than becoming a column.
   */
  metadataKey: string;
  metadataLabel: string;
  /** Where in this app the member already uses the property, if anywhere. */
  internalPath?: string;
  internalLabel?: string;
}

export const PROPERTIES: Property[] = [
  {
    key: 'str_domains',
    name: 'str.domains',
    host: 'str.domains',
    icon: Globe,
    summary: 'The registry that issues str.name identifiers.',
    grants: [
      'Mint and hold str.name domains against this identity',
      'List a domain on the IgniteHeX marketplace',
      'Use a held domain as the identifier on a CCoin network card',
    ],
    integration: 'linked',
    evidence:
      'Backed here by str_domains, str_domain_connections and domain_marketplace_listings. The per-domain links are listed below.',
    metadataKey: 'domain_name',
    metadataLabel: 'Primary domain',
    internalPath: '/marketplace',
    internalLabel: 'Marketplace',
  },
  {
    key: 'str_dome',
    name: 'strdome.com',
    host: 'strdome.com',
    icon: Signal,
    summary: 'str.dome — connectivity and eSIM delivery for domain holders.',
    grants: [
      'Order eSIM packages against a domain you already hold',
      'Have the profile delivered to your account email or wallet',
      'Carry one str.dome username across both properties',
    ],
    integration: 'linked',
    evidence:
      'Backed here by str_dome_requests, which the eSIM screen already writes and reads under your own identity.',
    metadataKey: 'str_dome_username',
    metadataLabel: 'str.dome username',
    internalPath: '/marketplace/esim',
    internalLabel: 'eSIM',
  },
  {
    key: 'ccoin_finance',
    name: 'ccoin.finance',
    host: 'ccoin.finance',
    icon: Coins,
    summary: 'The CCoin markets front end.',
    grants: [
      'Carry your verified identity onto the markets property',
      'Reference one account across both sides of a settlement',
    ],
    integration: 'record_only',
    /**
     * Searched for a backing table and found none: there is no ccoin_finance
     * table, no edge function naming the property and no column referencing it.
     * The link record can be held; nothing here can check it.
     */
    evidence:
      'No table, function or screen on this deployment belongs to ccoin.finance. A link record can be held, but nothing here can verify it against the property.',
    metadataKey: 'account_reference',
    metadataLabel: 'Account reference',
  },
  {
    key: 'ccoin_bank',
    name: 'CCoin Bank',
    host: 'ccoin.finance/bank',
    icon: Banknote,
    summary: 'Multi-currency accounts, cards and settlement.',
    grants: [
      'EUR, CHF and GBP accounts opened under this identity',
      'Prepaid and CCoin network cards',
      'Settlement written to the CCoin ledger',
    ],
    integration: 'linked',
    evidence:
      'Backed here by ccoin_bank_applications, ccoin_banking_profiles and the Banking domain. Opening an account is a separate application — this link records the identity tie, not the account.',
    metadataKey: 'account_reference',
    metadataLabel: 'Bank reference',
    internalPath: '/banking',
    internalLabel: 'Banking',
  },
];

/**
 * Values the CHECK constraint allows that this screen deliberately does not
 * offer. Named rather than silently dropped: if a row ever arrives carrying one
 * of these, the pages below list it under "other links" instead of hiding it.
 */
export const UNSURFACED_SERVICES = ['offshore_banking', 'onshore_banking'] as const;

export const PROPERTY_BY_KEY: Record<string, Property> = Object.fromEntries(
  PROPERTIES.map((p) => [p.key, p])
);

/** A readable name for any service value, including the two without cards. */
export function serviceName(service: string): string {
  return (
    PROPERTY_BY_KEY[service]?.name ??
    service.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase())
  );
}
