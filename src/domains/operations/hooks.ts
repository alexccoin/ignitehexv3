import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/features/auth/AuthProvider';
import type { Database } from '@/lib/database.types';
import { loadRequests, type RequestSource } from './requestSources';

/**
 * Operations data access.
 *
 * Two rules shape this file.
 *
 * 1. Decisions on member requests go through the v2_admin_* RPCs. They run
 *    SECURITY DEFINER with the authorisation check inside the function and they
 *    write the audit row themselves, so a decision cannot be forged by a client
 *    that simply skips the guard. v2 updated the request tables directly and
 *    left the audit trail to whoever remembered.
 *
 * 2. Role changes go through the `assign-role` edge function and nowhere else.
 *    v2 inserted into user_roles from the browser in ArxRoleManager.tsx:88 and
 *    deleted from it in AdminRoleAssignment.tsx:139, which meant anyone who
 *    could reach the page could grant themselves admin. In v3 user_roles is
 *    read-own-only, so those writes would now fail anyway.
 */

type Tables = Database['public']['Tables'];
export type AppRole = Database['public']['Enums']['app_role'];

export type AdminAction = Pick<
  Tables['v2_admin_actions']['Row'],
  'id' | 'entity_type' | 'entity_id' | 'action' | 'from_status' | 'to_status' | 'notes' | 'created_at' | 'actor_id'
>;

export type RequestMessage = Pick<
  Tables['v2_request_messages']['Row'],
  'id' | 'body' | 'sender_role' | 'requires_response' | 'created_at'
>;

export type GuardianWithdrawal = Pick<
  Tables['guardian_withdrawal_requests']['Row'],
  | 'id'
  | 'user_id'
  | 'asset_symbol'
  | 'amount'
  | 'network'
  | 'destination_address'
  | 'status'
  | 'requested_at'
  | 'window_expires_at'
  | 'processed_at'
  | 'admin_notes'
>;

export type SafeguardWallet = Pick<
  Tables['guardian_safeguard_wallets']['Row'],
  'id' | 'wallet_name' | 'wallet_type' | 'asset_symbol' | 'network' | 'wallet_address' | 'balance' | 'is_active' | 'updated_at'
>;

export type FlashAlert = Pick<
  Tables['guardian_flash_alerts']['Row'],
  | 'id'
  | 'alert_type'
  | 'asset_symbol'
  | 'title'
  | 'description'
  | 'severity'
  | 'status'
  | 'trigger_price'
  | 'market_price'
  | 'created_at'
>;

/** Namespaced by the domain id, so one invalidate clears the whole domain. */
const NS = 'operations';

export const oqk = {
  all: [NS] as const,
  requests: () => [NS, 'requests'] as const,
  requestHistory: () => [NS, 'request-history'] as const,
  requestMessages: (source: string, id: string) => [NS, 'request-messages', source, id] as const,
  myRoles: (userId: string) => [NS, 'my-roles', userId] as const,
  roleAudit: () => [NS, 'role-audit'] as const,
  approvalQueue: () => [NS, 'approval-queue'] as const,
  adminSessions: () => [NS, 'admin-sessions'] as const,
  reserveWallets: () => [NS, 'reserve-wallets'] as const,
  guardianWithdrawals: () => [NS, 'guardian-withdrawals'] as const,
  flashAlerts: () => [NS, 'flash-alerts'] as const,
  btcReserves: () => [NS, 'btc-reserves'] as const,
} as const;

function unwrap<T>({ data, error }: { data: T; error: { message: string } | null }): T {
  if (error) throw new Error(error.message);
  return data;
}

function useUserId(): string | null {
  const { user } = useAuth();
  return user?.id ?? null;
}

/* --------------------------------------------------------------- requests */

export function useRequests() {
  return useQuery({
    queryKey: oqk.requests(),
    queryFn: () => loadRequests(),
  });
}

/**
 * The two support queues on their own.
 *
 * Same loader, same RequestItem shape and the same server-side decision RPC as
 * the inbox — the support screen is a narrower view of the same data, not a
 * second implementation of it. v2 had AdminSupportTickets updating
 * member_support_tickets directly while AdminV2Requests decided the very same
 * rows through the RPC, so the two screens disagreed about the audit trail.
 */
export const SUPPORT_SOURCES = ['member_support_tickets', 'arx_support_tickets'] as const;

export function useSupportTickets() {
  return useQuery({
    queryKey: [...oqk.requests(), 'support'],
    queryFn: () => loadRequests(SUPPORT_SOURCES),
  });
}

/** The decision log, used to show what has already been done to a request. */
export function useRequestHistory(limit = 500) {
  return useQuery({
    queryKey: [...oqk.requestHistory(), limit],
    queryFn: async (): Promise<AdminAction[]> =>
      unwrap(
        await supabase
          .from('v2_admin_actions')
          .select('id, entity_type, entity_id, action, from_status, to_status, notes, created_at, actor_id')
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

export function useRequestMessages(source: RequestSource | null, requestId: string | null) {
  return useQuery({
    queryKey: oqk.requestMessages(source ?? '-', requestId ?? '-'),
    enabled: !!source && !!requestId,
    queryFn: async (): Promise<RequestMessage[]> =>
      unwrap(
        await supabase
          .from('v2_request_messages')
          .select('id, body, sender_role, requires_response, created_at')
          .eq('source', source!)
          .eq('request_id', requestId!)
          .order('created_at', { ascending: true })
      ) ?? [],
  });
}

export function useUpdateRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      source: RequestSource;
      id: string;
      status: string;
      notes?: string;
    }) => {
      const { error } = await supabase.rpc('v2_admin_update_request', {
        p_source: input.source,
        p_id: input.id,
        p_status: input.status,
        p_notes: input.notes?.trim() || undefined,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: oqk.all }),
  });
}

export interface BulkOutcome {
  updated: number;
  failed: number;
}

/**
 * Apply one status to many requests.
 *
 * The RPC takes a single source, so a mixed selection is split into one call
 * per source and each source gets the status that source actually understands.
 * v2 called it once with whatever source happened to be selected and fell back
 * to a literal "approved"/"rejected" for everything else, which wrote statuses
 * some of those tables do not use.
 */
export function useBulkUpdateRequests() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      batches: Array<{ source: RequestSource; ids: string[]; status: string }>;
      notes?: string;
    }): Promise<BulkOutcome> => {
      const outcome: BulkOutcome = { updated: 0, failed: 0 };

      for (const batch of input.batches) {
        if (batch.ids.length === 0) continue;
        const { data, error } = await supabase.rpc('v2_admin_bulk_update_requests', {
          p_source: batch.source,
          p_ids: batch.ids,
          p_status: batch.status,
          p_notes: input.notes?.trim() || undefined,
        });
        if (error) throw new Error(error.message);

        // The function returns json; read it defensively rather than casting.
        if (data && typeof data === 'object' && !Array.isArray(data)) {
          const record = data as Record<string, unknown>;
          outcome.updated += typeof record.updated === 'number' ? record.updated : 0;
          outcome.failed += typeof record.failed === 'number' ? record.failed : 0;
        }
      }

      return outcome;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: oqk.all }),
  });
}

export function useMessageRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      source: RequestSource;
      id: string;
      userId: string;
      body: string;
      requiresResponse: boolean;
      subject?: string;
    }) => {
      const { error } = await supabase.rpc('v2_admin_message_request', {
        p_source: input.source,
        p_id: input.id,
        p_user_id: input.userId,
        p_body: input.body,
        p_requires_response: input.requiresResponse,
        p_subject: input.subject,
      });
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: oqk.all }),
  });
}

/* ------------------------------------------------------------------ roles */

export interface AssignRoleResult {
  success?: boolean;
  error?: string;
  message?: string;
}

/**
 * Grant a role.
 *
 * The edge function re-derives the caller's identity from the bearer token,
 * checks `is_admin` server-side, resolves the email to a user and only then
 * writes user_roles with the service key. The browser never touches the table.
 */
export function useGrantRole() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { email: string; role: AppRole }): Promise<string> => {
      const { data, error } = await supabase.functions.invoke<AssignRoleResult>('assign-role', {
        body: { email: input.email.trim(), role: input.role },
      });
      if (error) throw new Error(error.message);
      if (data && data.success === false) {
        throw new Error(data.error ?? 'The role grant was refused.');
      }
      return data?.message ?? `${input.role} granted to ${input.email.trim()}.`;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: oqk.all }),
  });
}

/**
 * The signed-in administrator's own roles.
 *
 * This is the only role read the client can make: user_roles is read-own-only,
 * so there is no way to list who holds a role from the browser. v2 listed every
 * holder by querying the table directly, which is exactly the read that is now
 * closed.
 */
export function useMyRoles() {
  const userId = useUserId();
  return useQuery({
    queryKey: oqk.myRoles(userId ?? 'anon'),
    enabled: !!userId,
    queryFn: async () =>
      unwrap(
        await supabase
          .from('user_roles')
          .select('id, role, created_at, created_by')
          .eq('user_id', userId!)
          .order('created_at', { ascending: true })
      ) ?? [],
  });
}

/** Role changes as recorded by the security log, which is the durable record. */
export function useRoleAudit(limit = 50) {
  return useQuery({
    queryKey: [...oqk.roleAudit(), limit],
    queryFn: async () =>
      unwrap(
        await supabase
          .from('security_audit_log')
          .select('id, action, resource_type, resource_id, user_id, created_at')
          .eq('resource_type', 'user_roles')
          .order('created_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/* -------------------------------------------------------- ops dashboard */

export function useApprovalQueue() {
  return useQuery({
    queryKey: oqk.approvalQueue(),
    queryFn: async () =>
      unwrap(
        await supabase
          .from('admin_approval_queue')
          .select(
            'id, operation_type, risk_level, status, requesting_admin, approving_admin, target_user_id, requested_at, expires_at, executed_at'
          )
          .order('requested_at', { ascending: false })
          .limit(50)
      ) ?? [],
  });
}

export function useAdminSessions(limit = 15) {
  return useQuery({
    queryKey: [...oqk.adminSessions(), limit],
    queryFn: async () =>
      unwrap(
        await supabase
          .from('admin_session_log')
          .select('id, admin_user_id, login_at, logout_at, is_active, actions_performed, risk_score')
          .order('login_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

/* --------------------------------------------------------------- reserves */

export function useReserveWallets() {
  return useQuery({
    queryKey: oqk.reserveWallets(),
    queryFn: async (): Promise<SafeguardWallet[]> =>
      unwrap(
        await supabase
          .from('guardian_safeguard_wallets')
          .select(
            'id, wallet_name, wallet_type, asset_symbol, network, wallet_address, balance, is_active, updated_at'
          )
          .order('asset_symbol', { ascending: true })
      ) ?? [],
  });
}

export function useGuardianWithdrawals(limit = 100) {
  return useQuery({
    queryKey: [...oqk.guardianWithdrawals(), limit],
    queryFn: async (): Promise<GuardianWithdrawal[]> =>
      unwrap(
        await supabase
          .from('guardian_withdrawal_requests')
          .select(
            'id, user_id, asset_symbol, amount, network, destination_address, status, requested_at, window_expires_at, processed_at, admin_notes'
          )
          .order('requested_at', { ascending: false })
          .limit(limit)
      ) ?? [],
  });
}

export function useFlashAlerts() {
  return useQuery({
    queryKey: oqk.flashAlerts(),
    queryFn: async (): Promise<FlashAlert[]> =>
      unwrap(
        await supabase
          .from('guardian_flash_alerts')
          .select(
            'id, alert_type, asset_symbol, title, description, severity, status, trigger_price, market_price, created_at'
          )
          .in('status', ['active', 'acknowledged'])
          .order('created_at', { ascending: false })
          .limit(30)
      ) ?? [],
  });
}

/**
 * Acknowledge a market alert.
 *
 * This is the one direct table write in the domain. It flips a display flag on
 * a row RLS already restricts to administrators; nothing moves as a result, and
 * there is no server function that wraps it.
 */
export function useAcknowledgeAlert() {
  const userId = useUserId();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (alertId: string) => {
      const { error } = await supabase
        .from('guardian_flash_alerts')
        .update({
          status: 'acknowledged',
          acted_by: userId,
          acted_at: new Date().toISOString(),
          action_taken: 'acknowledged',
        })
        .eq('id', alertId)
        .eq('status', 'active');
      if (error) throw new Error(error.message);
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: oqk.flashAlerts() }),
  });
}

export interface ReserveWallet {
  address: string;
  label: string;
  type: string;
  /** Null when the chain could not be read for this address. Never 0. */
  balance: number | null;
  error: string | null;
}

export interface BtcReserves {
  wallets: ReserveWallet[];
  /** Null whenever any address failed — a partial sum is not a reserve total. */
  totalBtc: number | null;
  activeNodes: number;
  addressesTotal: number;
  addressesFailed: number;
  lastUpdated: string | null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function num(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function str(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

/**
 * On-chain reserve attestation.
 *
 * Read straight from the `btc-wallet-balances` function and rendered as
 * returned. v2's Proof of Reserve page subtracted a list of pending
 * withdrawals hardcoded in the page from the balances the chain reported, so
 * the "on-chain" figure on screen was not the figure on chain. Whatever this
 * shows is what the function said.
 *
 * The response is untyped json, so it is narrowed field by field rather than
 * cast.
 *
 * A BALANCE THE CHAIN COULD NOT REPORT IS NULL, NOT ZERO. The function used to
 * answer 0 for an address blockchain.info refused, so a rate-limit and an
 * emptied reserve rendered identically on a page whose whole purpose is to be
 * checkable. Nulls reach the screen as "Unavailable", and the total is withheld
 * entirely while any address is missing.
 */
export function useBtcReserves() {
  return useQuery({
    queryKey: oqk.btcReserves(),
    refetchInterval: 5 * 60_000,
    queryFn: async (): Promise<BtcReserves> => {
      const { data, error } = await supabase.functions.invoke<unknown>('btc-wallet-balances');
      if (error) throw new Error(error.message);

      const payload = asRecord(data);
      if (!payload) throw new Error('The reserve service returned an unexpected response.');

      const rawWallets = Array.isArray(payload.wallets) ? payload.wallets : [];
      const wallets: ReserveWallet[] = rawWallets.flatMap((entry) => {
        const record = asRecord(entry);
        if (!record) return [];
        return [
          {
            address: str(record.address),
            label: str(record.label) || str(record.name) || str(record.node) || 'Reserve wallet',
            type: str(record.type) || 'custody',
            // `num()` would turn a null balance into 0, which is exactly the
            // defect: an address the chain could not be read for would render
            // as an empty wallet on a proof-of-reserve screen.
            balance: typeof record.balance === 'number' ? record.balance : null,
            error: typeof record.error === 'string' ? record.error : null,
          },
        ];
      });

      const totals = asRecord(payload.totals);
      const failed = wallets.filter((wallet) => wallet.balance === null).length;

      // No total while any address is missing. A sum over the addresses that
      // did answer is a smaller number presented as the whole reserve.
      const totalBtc =
        failed > 0 || payload.success === false
          ? null
          : totals && typeof totals.total_btc === 'number'
            ? totals.total_btc
            : wallets.reduce((sum, w) => sum + (w.balance ?? 0), 0);

      return {
        wallets,
        totalBtc,
        activeNodes: totals ? num(totals.active_nodes) : wallets.length - failed,
        addressesTotal:
          totals && typeof totals.addresses_total === 'number'
            ? totals.addresses_total
            : wallets.length,
        addressesFailed:
          totals && typeof totals.addresses_failed === 'number'
            ? totals.addresses_failed
            : failed,
        lastUpdated: totals && typeof totals.last_updated === 'string' ? totals.last_updated : null,
      };
    },
  });
}
