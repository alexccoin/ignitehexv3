import { supabase } from '@/lib/supabase';
import type { Database } from '@/lib/database.types';
import { maskIban, money, shortDate, token } from '@/lib/format';

/**
 * The request inbox.
 *
 * Nine tables collect things a member has asked an administrator to decide.
 * v2 read them through one dynamic `supabase.from(s.key).select('*')` behind a
 * `const anyDb = supabase as any`, which meant the whole row of every table
 * reached the browser — raw IBANs, tax identification numbers, confirmation
 * tokens, encrypted payloads and all — and no column name was ever checked
 * against the schema.
 *
 * Here each source is loaded by its own statically-typed query that names the
 * columns the inbox actually renders, and each one maps its row onto the same
 * RequestItem shape. It is more code, but a renamed column is now a compile
 * error and nothing sensitive is fetched by accident.
 */

type Json = Database['public']['Tables']['pending_profile_changes']['Row']['requested_changes'];

export type RequestSource =
  | 'member_support_tickets'
  | 'arx_support_tickets'
  | 'missing_asset_reports'
  | 'pending_profile_changes'
  | 'user_profiles_updated'
  | 'staking_requests'
  | 'str_dome_requests'
  | 'withdrawal_requests'
  | 'ipo_listing_requests';

export type RequestGroup = 'support' | 'assets' | 'compliance';

export interface SourceDef {
  label: string;
  group: RequestGroup;
  /** Status written when an administrator approves. */
  approve: string;
  /** Status written when an administrator declines. */
  decline: string;
  /** Further statuses this source understands, offered as extra buttons. */
  extra: readonly string[];
  /** Statuses that count as still needing attention. */
  open: readonly string[];
}

export const SOURCES: Record<RequestSource, SourceDef> = {
  member_support_tickets: {
    label: 'Support tickets',
    group: 'support',
    approve: 'resolved',
    decline: 'rejected',
    extra: ['in_progress', 'escalated'],
    open: ['open', 'pending', 'in_progress', 'escalated', 'new'],
  },
  arx_support_tickets: {
    label: 'ARX tickets',
    group: 'support',
    approve: 'resolved',
    decline: 'closed',
    extra: ['in_progress', 'escalated'],
    open: ['open', 'pending', 'in_progress', 'escalated', 'new'],
  },
  missing_asset_reports: {
    label: 'Missing assets',
    group: 'assets',
    approve: 'approved',
    decline: 'rejected',
    extra: ['investigating'],
    open: ['pending', 'investigating', 'open', 'new'],
  },
  staking_requests: {
    label: 'Staking requests',
    group: 'assets',
    approve: 'approved',
    decline: 'rejected',
    extra: ['processing'],
    open: ['pending', 'processing', 'requested'],
  },
  str_dome_requests: {
    label: 'STR.Dome requests',
    group: 'assets',
    approve: 'delivered',
    decline: 'rejected',
    extra: ['processing', 'approved'],
    open: ['pending', 'processing', 'approved', 'new'],
  },
  withdrawal_requests: {
    label: 'Withdrawals',
    group: 'assets',
    approve: 'approved',
    decline: 'rejected',
    extra: ['processing', 'completed'],
    open: ['pending', 'processing', 'requested'],
  },
  ipo_listing_requests: {
    label: 'Listing requests',
    group: 'assets',
    approve: 'approved',
    decline: 'rejected',
    extra: ['processing', 'paid'],
    open: ['pending', 'processing', 'submitted', 'new'],
  },
  pending_profile_changes: {
    label: 'Profile changes',
    group: 'compliance',
    approve: 'approved',
    decline: 'rejected',
    extra: ['under_review', 'suspended'],
    open: ['pending', 'under_review', 'suspended', 'awaiting_confirmation'],
  },
  user_profiles_updated: {
    label: 'Profile resubmissions',
    group: 'compliance',
    approve: 'approved',
    decline: 'rejected',
    extra: ['under_review', 'suspended'],
    open: ['pending', 'submitted', 'under_review', 'suspended', 'new'],
  },
};

export const SOURCE_ORDER = Object.keys(SOURCES) as RequestSource[];

export const GROUP_LABELS: Record<RequestGroup, string> = {
  support: 'Support and complaints',
  assets: 'Assets and finance',
  compliance: 'Profile and compliance',
};

export interface RequestDetail {
  label: string;
  value: string;
}

export interface RequestItem {
  /** Unique across sources, since ids are only unique within a table. */
  key: string;
  source: RequestSource;
  id: string;
  userId: string;
  title: string;
  subtitle: string;
  status: string;
  createdAt: string;
  details: RequestDetail[];
  /** Free-text blob used by the search box, built from rendered values only. */
  haystack: string;
}

export function isOpen(item: RequestItem): boolean {
  return SOURCES[item.source].open.includes(item.status.toLowerCase());
}

/* ------------------------------------------------------------------ mapping */

/** Drop details with nothing in them so the pane does not fill with dashes. */
function detail(label: string, value: string | number | null | undefined): RequestDetail | null {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  if (!text) return null;
  return { label, value: text };
}

function details(...entries: Array<RequestDetail | null>): RequestDetail[] {
  return entries.filter((e): e is RequestDetail => e !== null);
}

function yesNo(value: boolean | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  return value ? 'Yes' : 'No';
}

/** Name the fields a profile change touches without dumping their values. */
function changedFields(value: Json): string | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const keys = Object.keys(value);
  if (keys.length === 0) return null;
  return keys.map((k) => k.replace(/_/g, ' ')).join(', ');
}

function build(
  source: RequestSource,
  row: { id: string; userId: string | null; status: string | null; createdAt: string | null },
  title: string,
  subtitle: string,
  rowDetails: RequestDetail[]
): RequestItem {
  const item: RequestItem = {
    key: `${source}:${row.id}`,
    source,
    id: row.id,
    userId: row.userId ?? '',
    title,
    subtitle,
    status: row.status ?? 'pending',
    createdAt: row.createdAt ?? new Date(0).toISOString(),
    details: rowDetails,
    haystack: '',
  };
  item.haystack = [title, subtitle, item.status, item.userId, ...rowDetails.map((d) => d.value)]
    .join(' ')
    .toLowerCase();
  return item;
}

/** Throw on a Supabase error so react-query can surface it. */
function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

const PAGE = 400;

/* ------------------------------------------------------------------ loaders */

async function loadMemberSupportTickets(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('member_support_tickets')
        .select(
          'id, user_id, user_email, full_name, str_domain, category, severity, error_details, status, admin_notes, created_at, resolved_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'member_support_tickets',
      { id: r.id, userId: r.user_id, status: r.status, createdAt: r.created_at },
      `Support · ${r.category.replace(/_/g, ' ')}`,
      r.full_name ?? r.user_email,
      details(
        detail('Severity', r.severity),
        detail('Email', r.user_email),
        detail('STR domain', r.str_domain),
        detail('Reported', r.error_details),
        detail('Admin notes', r.admin_notes),
        detail('Resolved', r.resolved_at ? shortDate(r.resolved_at) : null)
      )
    )
  );
}

async function loadArxSupportTickets(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('arx_support_tickets')
        .select(
          'id, submitted_by, ticket_number, subject, description, category, priority, status, escalation_level, sla_deadline, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'arx_support_tickets',
      { id: r.id, userId: r.submitted_by, status: r.status, createdAt: r.created_at },
      r.subject,
      `${r.ticket_number} · ${r.category}`,
      details(
        detail('Priority', r.priority),
        detail('Escalation level', r.escalation_level),
        detail('SLA deadline', r.sla_deadline ? shortDate(r.sla_deadline) : null),
        detail('Description', r.description)
      )
    )
  );
}

async function loadMissingAssetReports(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('missing_asset_reports')
        .select(
          'id, user_id, full_name, email_address, missing_crypto, starw_nodes_count, supernodes_count, transaction_hash, user_comment, admin_notes, status, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'missing_asset_reports',
      { id: r.id, userId: r.user_id, status: r.status, createdAt: r.created_at },
      'Missing assets',
      r.full_name ?? r.email_address ?? 'Unknown member',
      details(
        detail('Assets claimed', (r.missing_crypto ?? []).join(', ')),
        detail('STARW nodes', r.starw_nodes_count),
        detail('Supernodes', r.supernodes_count),
        detail('Transaction hash', r.transaction_hash),
        detail('Member comment', r.user_comment),
        detail('Admin notes', r.admin_notes)
      )
    )
  );
}

async function loadPendingProfileChanges(): Promise<RequestItem[]> {
  // confirmation_token and user_agent are deliberately not selected: the review
  // does not need them and the token is a credential.
  const rows =
    unwrap(
      await supabase
        .from('pending_profile_changes')
        .select('id, user_id, requested_changes, change_reason, admin_notes, status, created_at, reviewed_at')
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'pending_profile_changes',
      { id: r.id, userId: r.user_id, status: r.status, createdAt: r.created_at },
      'Profile change',
      r.change_reason ?? 'No reason given',
      details(
        detail('Fields changed', changedFields(r.requested_changes)),
        detail('Admin notes', r.admin_notes),
        detail('Reviewed', r.reviewed_at ? shortDate(r.reviewed_at) : null)
      )
    )
  );
}

async function loadUserProfilesUpdated(): Promise<RequestItem[]> {
  // tax_identification_number exists on this table and v2 rendered it. It is
  // not selected here: the reviewer needs the residency and the classification
  // to make the decision, not the number itself.
  const rows =
    unwrap(
      await supabase
        .from('user_profiles_updated')
        .select(
          'id, user_id, full_name, email_address, country, tax_residency_country, investor_classification, source_of_funds, source_of_wealth, expected_monthly_volume_eur, is_pep, sanctions_declaration, mica_terms_accepted, mica_terms_version, otp_verified, str_domain_owned, change_reason, admin_notes, rejection_reason, submission_status, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'user_profiles_updated',
      { id: r.id, userId: r.user_id, status: r.submission_status, createdAt: r.created_at },
      'Profile resubmission',
      r.full_name ?? r.email_address ?? 'Unknown member',
      details(
        detail('Country', r.country),
        detail('Tax residency', r.tax_residency_country),
        detail('Classification', r.investor_classification),
        detail('Source of funds', r.source_of_funds),
        detail('Source of wealth', r.source_of_wealth),
        detail(
          'Expected monthly volume',
          r.expected_monthly_volume_eur != null ? money(r.expected_monthly_volume_eur) : null
        ),
        detail('Politically exposed', yesNo(r.is_pep)),
        detail('Sanctions declaration', yesNo(r.sanctions_declaration)),
        detail(
          'MiCA terms',
          r.mica_terms_accepted ? `Accepted ${r.mica_terms_version ?? ''}`.trim() : 'Not accepted'
        ),
        detail('OTP verified', yesNo(r.otp_verified)),
        detail('STR domain', r.str_domain_owned),
        detail('Reason for change', r.change_reason),
        detail('Admin notes', r.admin_notes),
        detail('Rejection reason', r.rejection_reason)
      )
    )
  );
}

async function loadStakingRequests(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('staking_requests')
        .select(
          'id, user_id, full_name, pool_type, request_type, amount, duration_months, description, str_domain_owned, transaction_hash, admin_notes, status, created_at, requested_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'staking_requests',
      {
        id: r.id,
        userId: r.user_id,
        status: r.status,
        createdAt: r.created_at ?? r.requested_at,
      },
      `${r.request_type} · ${token(r.amount, r.pool_type)}`,
      r.full_name ?? r.str_domain_owned ?? 'Unknown member',
      details(
        detail('Pool', r.pool_type),
        detail('Duration', r.duration_months ? `${r.duration_months} months` : null),
        detail('STR domain', r.str_domain_owned),
        detail('Transaction hash', r.transaction_hash),
        detail('Description', r.description),
        detail('Admin notes', r.admin_notes)
      )
    )
  );
}

async function loadStrDomeRequests(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('str_dome_requests')
        .select(
          'id, user_id, str_dome_username, account_email, package_name, package_price_usd, esim_country, delivery_email, deliver_to_wallet, notes, admin_notes, status, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'str_dome_requests',
      { id: r.id, userId: r.user_id, status: r.status, createdAt: r.created_at },
      `STR.Dome · ${r.package_name}`,
      r.str_dome_username,
      details(
        detail('Price', money(r.package_price_usd, 'USD')),
        detail('eSIM country', r.esim_country),
        detail('Account email', r.account_email),
        detail('Delivery email', r.delivery_email),
        detail('Deliver to wallet', yesNo(r.deliver_to_wallet)),
        detail('Member notes', r.notes),
        detail('Admin notes', r.admin_notes)
      )
    )
  );
}

async function loadWithdrawalRequests(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('withdrawal_requests')
        .select(
          'id, user_id, btc_amount, usd_value_at_request, withdrawal_address, transaction_hash, status, created_at, requested_at, processed_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'withdrawal_requests',
      { id: r.id, userId: r.user_id, status: r.status, createdAt: r.created_at },
      `Withdrawal · ${token(r.btc_amount, 'BTC')}`,
      r.withdrawal_address,
      details(
        detail('Value at request', money(r.usd_value_at_request, 'USD')),
        detail('Destination', r.withdrawal_address),
        detail('Transaction hash', r.transaction_hash),
        detail('Requested', shortDate(r.requested_at)),
        detail('Processed', r.processed_at ? shortDate(r.processed_at) : null)
      )
    )
  );
}

async function loadIpoListingRequests(): Promise<RequestItem[]> {
  const rows =
    unwrap(
      await supabase
        .from('ipo_listing_requests')
        .select(
          'id, user_id, full_name, email, number_of_shares, share_type, price_per_share, total_usd_value, receiving_currency, iban, bank_name, bank_swift, admin_notes, admin_message, status, created_at'
        )
        .order('created_at', { ascending: false })
        .limit(PAGE)
    ) ?? [];

  return rows.map((r) =>
    build(
      'ipo_listing_requests',
      { id: r.id, userId: r.user_id, status: r.status, createdAt: r.created_at },
      `Listing · ${r.number_of_shares} ${r.share_type}`,
      r.full_name,
      details(
        detail('Email', r.email),
        detail('Price per share', money(r.price_per_share, 'USD')),
        detail('Total', money(r.total_usd_value, 'USD')),
        detail('Receiving currency', r.receiving_currency),
        // Masked: the reviewer needs to recognise the account, not read it out.
        detail('IBAN', maskIban(r.iban)),
        detail('Bank', r.bank_name),
        detail('SWIFT', r.bank_swift),
        detail('Message to member', r.admin_message),
        detail('Admin notes', r.admin_notes)
      )
    )
  );
}

const LOADERS: Record<RequestSource, () => Promise<RequestItem[]>> = {
  member_support_tickets: loadMemberSupportTickets,
  arx_support_tickets: loadArxSupportTickets,
  missing_asset_reports: loadMissingAssetReports,
  pending_profile_changes: loadPendingProfileChanges,
  user_profiles_updated: loadUserProfilesUpdated,
  staking_requests: loadStakingRequests,
  str_dome_requests: loadStrDomeRequests,
  withdrawal_requests: loadWithdrawalRequests,
  ipo_listing_requests: loadIpoListingRequests,
};

export interface RequestLoad {
  items: RequestItem[];
  /** Sources RLS or the network refused, so the count can be shown as partial. */
  failures: Array<{ source: RequestSource; message: string }>;
}

/**
 * Load every source in parallel.
 *
 * One source failing must not blank the whole inbox — v2's Promise.all meant a
 * single rejected table left the administrator with an empty screen and no
 * explanation. Failures are collected and reported alongside the results.
 */
export async function loadRequests(sources: readonly RequestSource[] = SOURCE_ORDER): Promise<RequestLoad> {
  const settled = await Promise.allSettled(sources.map((source) => LOADERS[source]()));

  const items: RequestItem[] = [];
  const failures: RequestLoad['failures'] = [];

  settled.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      items.push(...result.value);
    } else {
      failures.push({
        source: sources[index],
        message: result.reason instanceof Error ? result.reason.message : 'Unknown error',
      });
    }
  });

  items.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  return { items, failures };
}
