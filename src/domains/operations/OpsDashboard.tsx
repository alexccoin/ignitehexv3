import { useMemo } from 'react';
import { Link } from 'react-router-dom';
import { ClipboardList, Inbox, LifeBuoy, ShieldCheck, Vault } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { useAdminAccounts, useAdminClaims } from '@/hooks/data';
import { relativeTime, shortDate } from '@/lib/format';
import {
  useAdminSessions,
  useApprovalQueue,
  useFlashAlerts,
  useGuardianWithdrawals,
  useRequestHistory,
  useRequests,
} from './hooks';
import { GROUP_LABELS, SOURCES, SOURCE_ORDER, isOpen } from './requestSources';

const RISK_TONE: Record<string, 'danger' | 'warning' | 'info' | 'neutral'> = {
  critical: 'danger',
  high: 'danger',
  medium: 'warning',
  low: 'info',
};

export default function OpsDashboard() {
  // Reuses the shared admin hooks rather than re-querying v2_accounts and
  // v2_asset_claims here, so the review screens and this one share a cache.
  const accounts = useAdminAccounts('submitted');
  const claims = useAdminClaims('pending');
  const requests = useRequests();
  const approvals = useApprovalQueue();
  const history = useRequestHistory(30);
  const sessions = useAdminSessions();
  const withdrawals = useGuardianWithdrawals(50);
  const alerts = useFlashAlerts();

  const openItems = useMemo(() => (requests.data?.items ?? []).filter(isOpen), [requests.data]);

  const perSource = useMemo(() => {
    const counts = new Map<string, number>();
    for (const item of openItems) counts.set(item.source, (counts.get(item.source) ?? 0) + 1);
    return SOURCE_ORDER.map((source) => ({ source, count: counts.get(source) ?? 0 }));
  }, [openItems]);

  const openSupport = perSource
    .filter(({ source }) => SOURCES[source].group === 'support')
    .reduce((sum, entry) => sum + entry.count, 0);

  const pendingApprovals = (approvals.data ?? []).filter((row) => row.status === 'pending');
  const activeAlerts = (alerts.data ?? []).filter((row) => row.status === 'active');
  const pendingWithdrawals = (withdrawals.data ?? []).filter((row) => row.status === 'pending');

  return (
    <>
      <PageHeader
        title="Operations"
        description="What is waiting on an administrator right now."
        actions={
          <Button asChild variant="secondary">
            <Link to="/operations/requests">
              <Inbox />
              Open the inbox
            </Link>
          </Button>
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Accounts to review"
          value={(accounts.data ?? []).length}
          loading={accounts.isLoading}
          tone={(accounts.data ?? []).length > 0 ? 'warning' : 'default'}
          icon={<ShieldCheck className="size-4" />}
        />
        <Stat
          label="Asset claims"
          value={(claims.data ?? []).length}
          loading={claims.isLoading}
          icon={<ClipboardList className="size-4" />}
        />
        <Stat
          label="Open requests"
          value={openItems.length}
          loading={requests.isLoading}
          tone="primary"
          icon={<Inbox className="size-4" />}
        />
        <Stat
          label="Open tickets"
          value={openSupport}
          loading={requests.isLoading}
          icon={<LifeBuoy className="size-4" />}
        />
      </div>

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Pending approvals"
          value={pendingApprovals.length}
          loading={approvals.isLoading}
          tone={pendingApprovals.length > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Withdrawals waiting"
          value={pendingWithdrawals.length}
          loading={withdrawals.isLoading}
          icon={<Vault className="size-4" />}
        />
        <Stat
          label="Active market alerts"
          value={activeAlerts.length}
          loading={alerts.isLoading}
          tone={activeAlerts.length > 0 ? 'danger' : 'default'}
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-2 lg:items-start">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Queues</CardTitle>
              <CardDescription>Open items per request queue.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {requests.isLoading ? (
              <div className="p-5">
                <Skeleton className="h-56 w-full" />
              </div>
            ) : requests.isError ? (
              <ErrorState error={requests.error} onRetry={() => void requests.refetch()} />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Queue</TH>
                      <TH>Group</TH>
                      <TH className="text-right">Open</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {perSource.map(({ source, count }) => (
                      <TR key={source}>
                        <TD className="font-medium">{SOURCES[source].label}</TD>
                        <TD className="text-muted-foreground">
                          {GROUP_LABELS[SOURCES[source].group]}
                        </TD>
                        <TD className="tabular text-right">
                          {count > 0 ? (
                            <Badge tone={count > 10 ? 'warning' : 'primary'}>{count}</Badge>
                          ) : (
                            <span className="text-muted-foreground">0</span>
                          )}
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Recent decisions</CardTitle>
              <CardDescription>
                Written by the server functions, not by whoever remembered to log.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {history.isLoading ? (
              <div className="p-5">
                <Skeleton className="h-56 w-full" />
              </div>
            ) : history.isError ? (
              <ErrorState error={history.error} onRetry={() => void history.refetch()} />
            ) : (history.data ?? []).length === 0 ? (
              <EmptyState title="Nothing yet" description="No decision has been recorded." />
            ) : (
              <ul className="divide-y divide-border">
                {(history.data ?? []).map((entry) => (
                  <li key={entry.id} className="flex items-start justify-between gap-3 p-4">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{entry.action}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {entry.entity_type} · {entry.from_status ?? '—'} → {entry.to_status ?? '—'}
                      </p>
                    </div>
                    <span className="shrink-0 text-xs text-muted-foreground">
                      {relativeTime(entry.created_at)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Approval queue</CardTitle>
              <CardDescription>
                Privileged operations awaiting a second administrator.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {approvals.isLoading ? (
              <div className="p-5">
                <Skeleton className="h-40 w-full" />
              </div>
            ) : approvals.isError ? (
              <ErrorState error={approvals.error} onRetry={() => void approvals.refetch()} />
            ) : (approvals.data ?? []).length === 0 ? (
              <EmptyState
                title="Nothing queued"
                description="No privileged operation is waiting for a second signature."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Operation</TH>
                      <TH>Risk</TH>
                      <TH>Requested</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(approvals.data ?? []).map((row) => (
                      <TR key={row.id}>
                        <TD className="font-medium">{row.operation_type}</TD>
                        <TD>
                          <Badge tone={RISK_TONE[row.risk_level ?? ''] ?? 'neutral'}>
                            {row.risk_level ?? 'unknown'}
                          </Badge>
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(row.requested_at)}</TD>
                        <TD>
                          <StatusBadge status={row.status} />
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Administrator sessions</CardTitle>
              <CardDescription>Who has been in the console recently.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {sessions.isLoading ? (
              <div className="p-5">
                <Skeleton className="h-40 w-full" />
              </div>
            ) : sessions.isError ? (
              <ErrorState error={sessions.error} onRetry={() => void sessions.refetch()} />
            ) : (sessions.data ?? []).length === 0 ? (
              <EmptyState title="No sessions logged" description="The session log is empty." />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Administrator</TH>
                      <TH>Signed in</TH>
                      <TH className="text-right">Actions</TH>
                      <TH className="text-right">Risk</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(sessions.data ?? []).map((row) => (
                      <TR key={row.id}>
                        <TD className="font-mono text-xs text-muted-foreground">
                          {row.admin_user_id.slice(0, 8)}…
                          {row.is_active && (
                            <Badge tone="success" className="ml-2">
                              Active
                            </Badge>
                          )}
                        </TD>
                        <TD className="text-muted-foreground">{relativeTime(row.login_at)}</TD>
                        <TD className="tabular text-right">{row.actions_performed ?? 0}</TD>
                        <TD className="tabular text-right">{row.risk_score ?? 0}</TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
