import { useMemo } from 'react';
import { toast } from 'sonner';
import { Bell, ExternalLink, Lock, RefreshCw, ShieldCheck, Vault } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { relativeTime, shortDate, token } from '@/lib/format';
import {
  useAcknowledgeAlert,
  useBtcReserves,
  useFlashAlerts,
  useGuardianWithdrawals,
  useReserveWallets,
} from './hooks';

const SEVERITY_TONE: Record<string, 'danger' | 'warning' | 'info' | 'neutral'> = {
  critical: 'danger',
  high: 'danger',
  medium: 'warning',
  low: 'info',
};

/** Show enough of an address to recognise it without filling the column. */
function shortAddress(address: string | null | undefined): string {
  if (!address) return '—';
  if (address.length <= 16) return address;
  return `${address.slice(0, 8)}…${address.slice(-6)}`;
}

function OnChainReserves() {
  const reserves = useBtcReserves();

  return (
    <Card className="mb-6">
      <CardHeader>
        <div className="space-y-1">
          <CardTitle>On-chain attestation</CardTitle>
          <CardDescription>
            Balances as the chain reports them, refreshed every five minutes.
          </CardDescription>
        </div>
        <Button
          variant="secondary"
          size="sm"
          onClick={() => void reserves.refetch()}
          disabled={reserves.isFetching}
        >
          <RefreshCw />
          Refresh
        </Button>
      </CardHeader>

      <CardContent className="p-0">
        {reserves.isLoading ? (
          <div className="p-5">
            <Skeleton className="h-32 w-full" />
          </div>
        ) : reserves.isError ? (
          <ErrorState
            title="Could not reach the reserve service"
            error={reserves.error}
            onRetry={() => void reserves.refetch()}
          />
        ) : (reserves.data?.wallets ?? []).length === 0 ? (
          <EmptyState
            title="No reserve wallets reported"
            description="The reserve service returned no wallets."
          />
        ) : (
          <>
            <div className="grid gap-4 p-5 sm:grid-cols-3">
              {/* Null total = at least one address unread. Printing the sum of
                  the rest would understate the reserve without saying so. */}
              <Stat
                label="Total reserves"
                value={
                  reserves.data && reserves.data.totalBtc !== null
                    ? token(reserves.data.totalBtc, 'BTC')
                    : 'Withheld'
                }
                sub={
                  reserves.data && reserves.data.totalBtc === null
                    ? 'An address could not be read — no total is shown'
                    : undefined
                }
                tone={reserves.data && reserves.data.totalBtc === null ? 'danger' : 'primary'}
              />
              <Stat
                label="Reporting nodes"
                value={
                  reserves.data
                    ? `${reserves.data.activeNodes} of ${reserves.data.addressesTotal}`
                    : '—'
                }
                tone={
                  reserves.data && reserves.data.addressesFailed > 0 ? 'warning' : 'default'
                }
              />
              <Stat
                label="Last on-chain sync"
                value={reserves.data?.lastUpdated ? relativeTime(reserves.data.lastUpdated) : '—'}
              />
            </div>

            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Node</TH>
                    <TH>Type</TH>
                    <TH>Address</TH>
                    <TH className="text-right">Balance</TH>
                    <TH className="text-right">Verify</TH>
                  </TR>
                </THead>
                <TBody>
                  {(reserves.data?.wallets ?? []).map((wallet) => (
                    <TR key={wallet.address || wallet.label}>
                      <TD className="font-medium">{wallet.label}</TD>
                      <TD className="text-muted-foreground">{wallet.type}</TD>
                      <TD className="font-mono text-xs text-muted-foreground">
                        {shortAddress(wallet.address)}
                      </TD>
                      <TD className="tabular text-right">
                        {wallet.balance === null ? (
                          <span className="font-medium text-danger">
                            Unavailable
                            <span className="mt-0.5 block max-w-56 whitespace-normal break-words text-right text-xs font-normal text-muted-foreground">
                              {wallet.error ?? 'the chain could not be read for this address'}
                            </span>
                          </span>
                        ) : (
                          token(wallet.balance, 'BTC')
                        )}
                      </TD>
                      <TD className="text-right">
                        {wallet.address ? (
                          <Button asChild variant="ghost" size="icon">
                            <a
                              href={`https://mempool.space/address/${wallet.address}`}
                              target="_blank"
                              rel="noreferrer noopener"
                              aria-label={`Verify ${wallet.label} on a block explorer`}
                            >
                              <ExternalLink />
                            </a>
                          </Button>
                        ) : (
                          '—'
                        )}
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          </>
        )}
      </CardContent>
    </Card>
  );
}

export default function Reserves() {
  const wallets = useReserveWallets();
  const withdrawals = useGuardianWithdrawals();
  const alerts = useFlashAlerts();
  const acknowledge = useAcknowledgeAlert();

  const pending = useMemo(
    () => (withdrawals.data ?? []).filter((w) => w.status === 'pending' || w.status === 'processing'),
    [withdrawals.data]
  );

  const custodyTotal = useMemo(
    () => (wallets.data ?? []).filter((w) => w.is_active).length,
    [wallets.data]
  );

  const activeAlerts = (alerts.data ?? []).filter((a) => a.status === 'active');

  async function ack(alertId: string) {
    try {
      await acknowledge.mutateAsync(alertId);
      toast.success('Alert acknowledged.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not acknowledge the alert');
    }
  }

  return (
    <>
      <PageHeader
        title="Reserves"
        description="Custody wallets, the withdrawal queue and market alerts."
      />

      {/* v2 put this behind AresGuardianPasswordGate: one password, shared by
          everyone who needed the page, exchanged for a token in sessionStorage.
          It hid the UI without protecting anything — the page's data sat in the
          bundle regardless. Access is a role now, checked on the route. */}
      <Card className="mb-6">
        <CardContent className="flex items-start gap-3 py-4">
          <ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" />
          <p className="text-sm text-muted-foreground">
            This page is reached by holding the administrator role, checked on the route and enforced
            again by the database on every row it reads. There is no shared vault password.
          </p>
        </CardContent>
      </Card>

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Custody wallets"
          value={custodyTotal}
          loading={wallets.isLoading}
          icon={<Vault className="size-4" />}
        />
        <Stat
          label="Withdrawals in flight"
          value={pending.length}
          loading={withdrawals.isLoading}
          tone={pending.length > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Active alerts"
          value={activeAlerts.length}
          loading={alerts.isLoading}
          tone={activeAlerts.length > 0 ? 'danger' : 'default'}
          icon={<Bell className="size-4" />}
        />
        <Stat
          label="Requests on record"
          value={(withdrawals.data ?? []).length}
          loading={withdrawals.isLoading}
        />
      </div>

      <OnChainReserves />

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Custody wallets</CardTitle>
            <CardDescription>The safeguard register held in the database.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {wallets.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-32 w-full" />
            </div>
          ) : wallets.isError ? (
            <ErrorState error={wallets.error} onRetry={() => void wallets.refetch()} />
          ) : (wallets.data ?? []).length === 0 ? (
            <EmptyState title="No custody wallets" description="The safeguard register is empty." />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Wallet</TH>
                    <TH>Asset</TH>
                    <TH>Network</TH>
                    <TH>Address</TH>
                    <TH className="text-right">Balance</TH>
                    <TH>State</TH>
                  </TR>
                </THead>
                <TBody>
                  {(wallets.data ?? []).map((wallet) => (
                    <TR key={wallet.id}>
                      <TD>
                        <p className="font-medium">{wallet.wallet_name}</p>
                        <p className="text-xs text-muted-foreground">{wallet.wallet_type}</p>
                      </TD>
                      <TD className="text-muted-foreground">{wallet.asset_symbol}</TD>
                      <TD className="text-muted-foreground">{wallet.network}</TD>
                      <TD className="font-mono text-xs text-muted-foreground">
                        {shortAddress(wallet.wallet_address)}
                      </TD>
                      <TD className="tabular text-right">
                        {token(wallet.balance, wallet.asset_symbol)}
                      </TD>
                      <TD>
                        <Badge tone={wallet.is_active ? 'success' : 'neutral'}>
                          {wallet.is_active ? 'Active' : 'Retired'}
                        </Badge>
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Withdrawal queue</CardTitle>
            <CardDescription>Read-only. See the note below.</CardDescription>
          </div>
          <Badge tone="warning">
            <Lock className="size-3" />
            No decision path
          </Badge>
        </CardHeader>
        <CardContent className="p-0">
          <div className="border-b border-border px-5 pb-4 text-sm text-muted-foreground">
            Approving one of these moves customer funds, and nothing on the server performs that
            move: there is no function that debits the wallet, broadcasts the transaction and marks
            the row in one authorised step. Flipping the status from the browser would tell an
            operator the payout had been made when nothing had happened, so the decision buttons are
            left out until such a function exists.
          </div>

          {withdrawals.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-32 w-full" />
            </div>
          ) : withdrawals.isError ? (
            <ErrorState error={withdrawals.error} onRetry={() => void withdrawals.refetch()} />
          ) : (withdrawals.data ?? []).length === 0 ? (
            <EmptyState title="Nothing queued" description="No withdrawal has been requested." />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Asset</TH>
                    <TH className="text-right">Amount</TH>
                    <TH>Network</TH>
                    <TH>Destination</TH>
                    <TH>Requested</TH>
                    <TH>Window closes</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {(withdrawals.data ?? []).map((request) => (
                    <TR key={request.id}>
                      <TD className="font-medium">{request.asset_symbol}</TD>
                      <TD className="tabular text-right">
                        {token(request.amount, request.asset_symbol)}
                      </TD>
                      <TD className="text-muted-foreground">{request.network}</TD>
                      <TD className="font-mono text-xs text-muted-foreground">
                        {shortAddress(request.destination_address)}
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(request.requested_at)}</TD>
                      <TD className="text-muted-foreground">
                        {relativeTime(request.window_expires_at)}
                      </TD>
                      <TD>
                        <StatusBadge status={request.status} />
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
            <CardTitle>Market alerts</CardTitle>
            <CardDescription>Price and liquidity warnings raised against the reserves.</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {alerts.isLoading ? (
            <Skeleton className="h-24 w-full" />
          ) : alerts.isError ? (
            <ErrorState error={alerts.error} onRetry={() => void alerts.refetch()} />
          ) : (alerts.data ?? []).length === 0 ? (
            <EmptyState
              title="No alerts"
              description="Nothing has been raised against the reserves."
              icon={<Bell className="size-5" />}
            />
          ) : (
            <ul className="space-y-3">
              {(alerts.data ?? []).map((alert) => (
                <li
                  key={alert.id}
                  className="flex flex-wrap items-start justify-between gap-3 rounded-md border border-border p-3"
                >
                  <div className="min-w-0">
                    <div className="mb-1 flex flex-wrap items-center gap-2">
                      <Badge tone={SEVERITY_TONE[alert.severity] ?? 'neutral'}>{alert.severity}</Badge>
                      <Badge tone="neutral">{alert.alert_type.replace(/_/g, ' ')}</Badge>
                      <Badge tone="neutral">{alert.asset_symbol}</Badge>
                      <StatusBadge status={alert.status} />
                    </div>
                    <p className="font-medium">{alert.title}</p>
                    {alert.description && (
                      <p className="text-sm text-muted-foreground">{alert.description}</p>
                    )}
                    <p className="mt-1 text-xs text-muted-foreground">
                      {alert.trigger_price != null && `Trigger ${alert.trigger_price} · `}
                      {alert.market_price != null && `Market ${alert.market_price} · `}
                      {relativeTime(alert.created_at)}
                    </p>
                  </div>
                  {alert.status === 'active' && (
                    <Button
                      size="sm"
                      variant="secondary"
                      disabled={acknowledge.isPending}
                      onClick={() => void ack(alert.id)}
                    >
                      Acknowledge
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </>
  );
}
