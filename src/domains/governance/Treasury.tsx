import { useMemo } from 'react';
import { Landmark, Lock, ShieldAlert } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate, token } from '@/lib/format';
import { useTreasuryPools, useTreasuryTransactions } from './hooks';

export default function Treasury() {
  const pools = useTreasuryPools();
  const transactions = useTreasuryTransactions();

  const totals = useMemo(() => {
    const rows = pools.data ?? [];
    return {
      usd: rows.reduce((sum, p) => sum + Number(p.balance_usd ?? 0), 0),
      arx: rows.reduce((sum, p) => sum + Number(p.balance_arx ?? 0), 0),
      locked: rows.reduce((sum, p) => sum + Number(p.locked_amount ?? 0), 0),
      pools: rows.length,
    };
  }, [pools.data]);

  const poolNames = useMemo(
    () => new Map((pools.data ?? []).map((p) => [p.id, p.pool_name])),
    [pools.data]
  );

  const awaitingSignature = (transactions.data ?? []).filter((t) => t.status === 'pending').length;

  return (
    <>
      <PageHeader
        title="Treasury"
        description="Club reserves, their lock schedules and the multisig ledger."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Reserves"
          value={money(totals.usd, 'USD')}
          sub={`Across ${totals.pools} pool${totals.pools === 1 ? '' : 's'}`}
          loading={pools.isLoading}
          icon={<Landmark className="size-4" />}
        />
        <Stat label="ARX held" value={token(totals.arx, 'ARX')} loading={pools.isLoading} />
        <Stat
          label="Locked"
          value={money(totals.locked, 'USD')}
          loading={pools.isLoading}
          tone="warning"
          icon={<Lock className="size-4" />}
        />
        <Stat
          label="Awaiting signatures"
          value={awaitingSignature}
          loading={transactions.isLoading}
          tone={awaitingSignature > 0 ? 'warning' : 'default'}
        />
      </div>

      {/* Movements are initiated and signed off-platform through the multisig.
          There is no server function that would let this screen propose or
          co-sign one, so the treasury is presented read-only rather than with
          buttons that could only fail. */}
      <Card className="mb-6">
        <CardContent className="flex items-start gap-3 py-4">
          <ShieldAlert className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Treasury movements are proposed and co-signed through the multisig, not from this
            console. This page reports the ledger; it cannot initiate or approve a transfer.
          </p>
        </CardContent>
      </Card>

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Pools</CardTitle>
            <CardDescription>Every reserve pool and the signatures each one requires.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {pools.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-32 w-full" />
            </div>
          ) : pools.isError ? (
            <ErrorState error={pools.error} onRetry={() => void pools.refetch()} />
          ) : (pools.data ?? []).length === 0 ? (
            <EmptyState
              title="No pools"
              description="The treasury register is empty."
              icon={<Landmark className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Pool</TH>
                    <TH>Type</TH>
                    <TH className="text-right">USD</TH>
                    <TH className="text-right">ARX</TH>
                    <TH className="text-right">ARS</TH>
                    <TH className="text-right">Locked</TH>
                    <TH>Multisig</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {(pools.data ?? []).map((pool) => (
                    <TR key={pool.id}>
                      <TD>
                        <p className="font-medium">{pool.pool_name}</p>
                        <p className="text-xs text-muted-foreground">
                          Updated {shortDate(pool.updated_at)}
                        </p>
                      </TD>
                      <TD className="text-muted-foreground">{pool.pool_type}</TD>
                      <TD className="tabular text-right">{money(pool.balance_usd, 'USD')}</TD>
                      <TD className="tabular text-right">{token(pool.balance_arx, 'ARX')}</TD>
                      <TD className="tabular text-right">{token(pool.balance_ars, 'ARS')}</TD>
                      <TD className="tabular text-right">{money(pool.locked_amount, 'USD')}</TD>
                      <TD>
                        <Badge tone="neutral">{pool.multisig_threshold} signatures</Badge>
                      </TD>
                      <TD>
                        <StatusBadge status={pool.status} />
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
            <CardTitle>Ledger</CardTitle>
            <CardDescription>The 50 most recent treasury movements.</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          {transactions.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-32 w-full" />
            </div>
          ) : transactions.isError ? (
            <ErrorState error={transactions.error} onRetry={() => void transactions.refetch()} />
          ) : (transactions.data ?? []).length === 0 ? (
            <EmptyState title="No movements" description="Nothing has moved through the treasury." />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Type</TH>
                    <TH>Pool</TH>
                    <TH className="text-right">Amount</TH>
                    <TH className="text-right">USD</TH>
                    <TH>Signatures</TH>
                    <TH>Opened</TH>
                    <TH>Executed</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {(transactions.data ?? []).map((txn) => (
                    <TR key={txn.id}>
                      <TD className="font-medium">{txn.transaction_type}</TD>
                      <TD className="text-muted-foreground">
                        {poolNames.get(txn.pool_id) ?? 'Unknown pool'}
                      </TD>
                      <TD className="tabular text-right">{token(txn.amount, txn.currency)}</TD>
                      <TD className="tabular text-right">{money(txn.usd_equivalent, 'USD')}</TD>
                      <TD className="text-muted-foreground">{txn.required_signatures} required</TD>
                      <TD className="text-muted-foreground">{shortDate(txn.created_at)}</TD>
                      <TD className="text-muted-foreground">{shortDate(txn.executed_at)}</TD>
                      <TD>
                        <StatusBadge status={txn.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>
    </>
  );
}
