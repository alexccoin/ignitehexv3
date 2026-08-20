import { Link } from 'react-router-dom';
import {
  ArrowRight,
  Bell,
  Coins,
  KeyRound,
  Landmark,
  Snowflake,
  Vault,
  Wallet,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { ChartLegend, CompositionChart } from '@/components/ui/charts';
import { money, shortDate, token as fmtToken } from '@/lib/format';
import { Detail, MempoolLink, shortAddress } from './shared';
import {
  useFlashAlerts,
  useGuardianInvitations,
  useGuardianTransactions,
  useGuardianWallets,
  useRecoveryKeyStatus,
  useSafeguardWallets,
  useWithdrawalRequests,
} from './hooks';

/**
 * What the vault holds.
 *
 * Two things this page deliberately does not do, because v2's equivalent did
 * both. It does not create anything: `AresGuardian.tsx` inserted five
 * `guardian_wallets` rows for every visitor who had typed the shared password,
 * so the act of opening the page provisioned a portfolio. And it does not
 * invent an access decision: there is no password prompt and no `hasAccess`
 * state here, because the domain's `requiresRole` decided that before this
 * component was mounted, and RLS decides which rows the queries return.
 *
 * An operator with no wallets of their own therefore sees an empty state rather
 * than a freshly minted portfolio.
 */
export default function VaultOverview() {
  const wallets = useGuardianWallets();
  const transactions = useGuardianTransactions(8);
  const withdrawals = useWithdrawalRequests();
  const alerts = useFlashAlerts();
  const safeguards = useSafeguardWallets();
  const invitations = useGuardianInvitations();
  const recovery = useRecoveryKeyStatus();

  const rows = wallets.data ?? [];
  const totalUsd = rows.reduce((sum, w) => sum + Number(w.usd_value ?? 0), 0);
  const pendingWithdrawals = (withdrawals.data ?? []).filter((w) => w.status === 'pending');
  const openAlerts = (alerts.data ?? []).filter((a) => a.status === 'active');

  // Only assets carrying value are charted; a row of zero-length bars is noise.
  const composition = rows
    .filter((w) => Number(w.usd_value ?? 0) > 0)
    .map((w) => ({ label: w.asset_symbol, value: Number(w.usd_value ?? 0) }));

  return (
    <>
      <PageHeader
        title="Ares Guardian"
        description="Custody positions, the reserves behind them and the requests waiting on them."
        actions={
          <Button asChild variant="secondary" size="sm">
            <Link to="/guardian/reserves">
              Proof of reserve
              <ArrowRight />
            </Link>
          </Button>
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Vault value"
          value={money(totalUsd, 'USD')}
          sub={`${rows.length} asset${rows.length === 1 ? '' : 's'} held`}
          icon={<Vault className="size-4" />}
          loading={wallets.isLoading}
        />
        <Stat
          label="Pending withdrawals"
          value={String(pendingWithdrawals.length)}
          sub="Inside the 96-hour processing window"
          tone={pendingWithdrawals.length > 0 ? 'warning' : 'default'}
          icon={<Landmark className="size-4" />}
          loading={withdrawals.isLoading}
        />
        <Stat
          label="Open alerts"
          value={String(openAlerts.length)}
          sub="Market conditions needing a decision"
          tone={openAlerts.length > 0 ? 'danger' : 'default'}
          icon={<Bell className="size-4" />}
          loading={alerts.isLoading}
        />
        <Stat
          label="Recovery backup"
          value={recovery.data?.configured ? 'Configured' : 'Not configured'}
          sub={
            recovery.data?.configured
              ? `Last updated ${shortDate(recovery.data.updatedAt)}`
              : 'No recovery record for your account'
          }
          tone={recovery.data?.configured ? 'success' : 'warning'}
          icon={<KeyRound className="size-4" />}
          loading={recovery.isLoading}
        />
      </div>

      <div className="mb-6 grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <div>
              <CardTitle>Holdings</CardTitle>
              <CardDescription>
                Balance is what the vault records. External balance is what the member's own
                address holds — the two are shown side by side rather than added together.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="pt-3">
            {wallets.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : wallets.isError ? (
              <ErrorState
                title="Could not load the vault"
                error={wallets.error}
                onRetry={() => void wallets.refetch()}
              />
            ) : rows.length === 0 ? (
              <EmptyState
                icon={<Wallet className="size-5" />}
                title="No guardian wallets"
                description="Guardian wallets are opened for a member by an operator. Nothing is provisioned by visiting this page."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Asset</TH>
                      <TH>Network</TH>
                      <TH className="text-right">Vault balance</TH>
                      <TH className="text-right">External</TH>
                      <TH className="text-right">Value</TH>
                      <TH>Address</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {rows.map((w) => (
                      <TR key={w.id}>
                        <TD>
                          <p className="font-medium">{w.asset_symbol}</p>
                          <p className="text-xs text-muted-foreground">{w.asset_name}</p>
                        </TD>
                        <TD className="text-muted-foreground">{w.network}</TD>
                        <TD className="tabular whitespace-nowrap text-right">
                          {fmtToken(Number(w.balance ?? 0), w.asset_symbol)}
                        </TD>
                        <TD className="tabular whitespace-nowrap text-right text-muted-foreground">
                          {fmtToken(Number(w.external_balance ?? 0), w.asset_symbol)}
                        </TD>
                        <TD className="tabular whitespace-nowrap text-right font-medium">
                          {money(Number(w.usd_value ?? 0), 'USD')}
                        </TD>
                        <TD className="font-mono text-xs text-muted-foreground">
                          {shortAddress(w.wallet_address ?? w.deposit_address)}
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
            <div>
              <CardTitle>Composition</CardTitle>
              <CardDescription>Share of vault value by asset, in USD.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 pt-3">
            {wallets.isLoading ? (
              <Skeleton className="h-48 w-full" />
            ) : wallets.isError ? (
              <ErrorState error={wallets.error} onRetry={() => void wallets.refetch()} />
            ) : composition.length === 0 ? (
              <EmptyState
                icon={<Coins className="size-5" />}
                title="Nothing to chart"
                description="No held asset currently carries a recorded USD value."
              />
            ) : (
              <>
                <CompositionChart
                  data={composition}
                  height={Math.max(160, composition.length * 34)}
                  format={(v) => money(v, 'USD')}
                />
                <ChartLegend items={composition.map((c, i) => ({ label: c.label, index: i }))} />
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Recent movements</CardTitle>
              <CardDescription>The guardian ledger only.</CardDescription>
            </div>
            <Button asChild variant="ghost" size="sm">
              <Link to="/guardian/withdrawals">Withdrawals</Link>
            </Button>
          </CardHeader>
          <CardContent className="pt-3">
            {transactions.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : transactions.isError ? (
              <ErrorState error={transactions.error} onRetry={() => void transactions.refetch()} />
            ) : (transactions.data ?? []).length === 0 ? (
              <EmptyState title="Nothing has moved yet" />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Date</TH>
                      <TH>Type</TH>
                      <TH className="text-right">Amount</TH>
                      <TH>Status</TH>
                      <TH className="text-right">Proof</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(transactions.data ?? []).map((t) => (
                      <TR key={t.id}>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {shortDate(t.created_at)}
                        </TD>
                        <TD>
                          <Badge tone="neutral">{t.transaction_type}</Badge>
                        </TD>
                        <TD className="tabular whitespace-nowrap text-right">
                          {fmtToken(Number(t.amount), t.asset_symbol)}
                        </TD>
                        <TD>
                          <StatusBadge status={t.status} />
                        </TD>
                        <TD className="text-right">
                          {t.tx_hash ? (
                            <a
                              href={`https://mempool.space/tx/${encodeURIComponent(t.tx_hash)}`}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-xs text-primary hover:underline"
                            >
                              {t.tx_hash.slice(0, 10)}…
                            </a>
                          ) : (
                            /* No hash means the movement was never broadcast, or
                               was booked internally. Saying so is better than
                               rendering a placeholder that looks like proof. */
                            <span className="text-xs text-muted-foreground">Not on chain</span>
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

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Safeguard wallets</CardTitle>
                <CardDescription>
                  Cold storage and reserve addresses, as recorded in the database.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-3 pt-3">
              {safeguards.isLoading ? (
                <>
                  <Skeleton className="h-16 w-full" />
                  <Skeleton className="h-16 w-full" />
                </>
              ) : safeguards.isError ? (
                <ErrorState error={safeguards.error} onRetry={() => void safeguards.refetch()} />
              ) : (safeguards.data ?? []).length === 0 ? (
                <EmptyState
                  icon={<Snowflake className="size-5" />}
                  title="No safeguard wallets registered"
                  description="Reserve addresses appear here once an operator records them."
                />
              ) : (
                (safeguards.data ?? []).map((s) => (
                  <div key={s.id} className="rounded-lg border border-border p-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="min-w-0">
                        <p className="truncate font-medium">{s.wallet_name}</p>
                        <p className="text-xs text-muted-foreground">
                          {s.wallet_type} · {s.network}
                        </p>
                      </div>
                      <span className="tabular shrink-0 text-sm font-medium">
                        {fmtToken(Number(s.balance ?? 0), s.asset_symbol)}
                      </span>
                    </div>
                    <div className="mt-2 flex flex-wrap items-center gap-3">
                      <span className="font-mono text-xs text-muted-foreground">
                        {shortAddress(s.wallet_address)}
                      </span>
                      <MempoolLink address={s.wallet_address} />
                    </div>
                  </div>
                ))
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div>
                <CardTitle>Access invitations</CardTitle>
                <CardDescription>
                  Who has been invited into the vault. Membership is granted by invitation and by
                  role, never by a shared password.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="pt-3">
              {invitations.isLoading ? (
                <div className="space-y-2">
                  <Skeleton className="h-10 w-full" />
                  <Skeleton className="h-10 w-full" />
                </div>
              ) : invitations.isError ? (
                <ErrorState error={invitations.error} onRetry={() => void invitations.refetch()} />
              ) : (invitations.data ?? []).length === 0 ? (
                <EmptyState title="No invitations" description="Nobody has been invited yet." />
              ) : (
                <div className="space-y-3">
                  {(invitations.data ?? []).map((inv) => (
                    <div
                      key={inv.id}
                      className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-3"
                    >
                      <Detail
                        label="Invited"
                        value={inv.invited_str_domain ?? inv.invited_email ?? '—'}
                      />
                      <Detail label="Expires" value={shortDate(inv.expires_at)} />
                      <StatusBadge status={inv.status} />
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  );
}
