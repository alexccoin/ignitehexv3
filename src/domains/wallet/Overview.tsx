import { Link } from 'react-router-dom';
import { ArrowRight, Banknote, Coins, Landmark, Lock, Wallet } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { useStakingPools, useTransactions } from '@/hooks/data';
import { useAuth } from '@/features/auth/AuthProvider';
import { largestPosition, byToken } from '@/lib/balances';
import { money, token as fmtToken, shortDate } from '@/lib/format';
import { useAvailableBalances, useFiatWallets, useIbanAccounts } from './hooks';

/**
 * What the member has.
 *
 * The three v2 wallet screens each computed the headline figure differently —
 * one added rewards for wSTR only, one overwrote the pool sum with the RPC, one
 * treated `staked_amount || balance` as staked so an unstaked pool counted its
 * liquid balance twice. This page derives everything from
 * `positionsFromPools`, and shows the server's spendable figure beside it
 * instead of subtracting one from the other.
 */
export default function WalletOverview() {
  const { user } = useAuth();
  const pools = useStakingPools();
  const available = useAvailableBalances();
  const fiat = useFiatWallets();
  const ibans = useIbanAccounts();
  const txns = useTransactions(8);

  const positions = pools.data?.positions ?? [];
  const holdings = largestPosition(positions);
  const fiatTotal = (fiat.data ?? []).reduce((sum, w) => sum + Number(w.balance ?? 0), 0);
  const accountCount = (fiat.data ?? []).length + (ibans.data ?? []).length;

  return (
    <>
      <PageHeader
        title="Wallet"
        description="Token positions, cash balances and the accounts they settle through."
        actions={
          <Button asChild variant="secondary" size="sm">
            <Link to="/wallet/transfers">
              Send or convert
              <ArrowRight />
            </Link>
          </Button>
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Largest holding"
          value={holdings ? fmtToken(holdings.total, holdings.token) : '—'}
          sub={`${positions.length} position${positions.length === 1 ? '' : 's'}`}
          icon={<Coins className="size-4" />}
          loading={pools.isLoading}
        />
        <Stat
          label="Staked"
          value={byToken(positions, 'staked', fmtToken)}
          sub="Locked in a staking position"
          icon={<Lock className="size-4" />}
          loading={pools.isLoading}
        />
        <Stat
          label="Cash"
          value={money(fiatTotal)}
          sub={`${(fiat.data ?? []).length} fiat wallet${(fiat.data ?? []).length === 1 ? '' : 's'}`}
          icon={<Banknote className="size-4" />}
          loading={fiat.isLoading}
        />
        <Stat
          label="Accounts"
          value={String(accountCount)}
          sub="Fiat wallets and IBANs"
          icon={<Landmark className="size-4" />}
          loading={fiat.isLoading || ibans.isLoading}
        />
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div>
            <CardTitle>Holdings</CardTitle>
            <CardDescription>
              Total is liquid plus escrow — the tokens you hold, plus the ones locked against a
              marketplace listing that is still yours until it settles. Staked is the principal as
              first credited and rewards are already inside liquid, so neither is added again
              (they were, and the same tokens were counted three times). Available is what the
              server says you can spend right now.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="pt-3">
          {pools.isLoading ? (
            <div className="space-y-2">
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-10 w-full" />
            </div>
          ) : pools.isError ? (
            <ErrorState
              title="Could not load your holdings"
              error={pools.error}
              onRetry={() => void pools.refetch()}
            />
          ) : positions.length === 0 ? (
            <EmptyState
              icon={<Wallet className="size-5" />}
              title="No positions yet"
              description="Once a staking pool is opened for you, its balance appears here."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Token</TH>
                    <TH className="text-right">Liquid</TH>
                    <TH className="text-right">In escrow</TH>
                    <TH className="text-right">Staked</TH>
                    <TH className="text-right">Rewards</TH>
                    <TH className="text-right">Total</TH>
                    <TH className="text-right">Available</TH>
                  </TR>
                </THead>
                <TBody>
                  {positions.map((p) => {
                    const spendable = available.data?.[p.token];
                    return (
                      <TR key={p.token}>
                        <TD className="font-medium uppercase">{p.token}</TD>
                        <TD className="tabular text-right">{fmtToken(p.liquid, p.token)}</TD>
                        <TD className="tabular text-right text-warning">
                          {fmtToken(p.escrowed, p.token)}
                        </TD>
                        <TD className="tabular text-right">{fmtToken(p.staked, p.token)}</TD>
                        <TD className="tabular text-right text-success">
                          {fmtToken(p.rewards, p.token)}
                        </TD>
                        <TD className="tabular text-right font-medium">{fmtToken(p.total, p.token)}</TD>
                        <TD className="tabular text-right">
                          {available.isLoading ? (
                            <Skeleton className="ml-auto h-4 w-20" />
                          ) : spendable === null || spendable === undefined ? (
                            /* Not 0 — the server did not answer, and pretending
                               it said zero is how v2 showed whole balances as
                               locked during a transient error. */
                            <span className="text-muted-foreground" title="The server did not return a figure">
                              Unavailable
                            </span>
                          ) : (
                            fmtToken(spendable, p.token)
                          )}
                        </TD>
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Cash balances</CardTitle>
              <CardDescription>Held is reserved against a pending transfer.</CardDescription>
            </div>
            <Button asChild variant="ghost" size="sm">
              <Link to="/wallet/accounts">Accounts</Link>
            </Button>
          </CardHeader>
          <CardContent className="space-y-3 pt-3">
            {fiat.isLoading ? (
              <>
                <Skeleton className="h-16 w-full" />
                <Skeleton className="h-16 w-full" />
              </>
            ) : fiat.isError ? (
              <ErrorState error={fiat.error} onRetry={() => void fiat.refetch()} />
            ) : (fiat.data ?? []).length === 0 ? (
              <EmptyState
                icon={<Banknote className="size-5" />}
                title="No cash balances"
                description="A fiat wallet is opened the first time funds settle to you."
              />
            ) : (
              (fiat.data ?? []).map((w) => (
                <div
                  key={w.id}
                  className="flex items-center justify-between gap-4 rounded-lg border border-border p-3"
                >
                  <div className="min-w-0">
                    <p className="font-medium">{w.currency}</p>
                    <p className="text-xs text-muted-foreground">
                      Available {money(Number(w.available_balance ?? 0), w.currency)}
                      {Number(w.held_balance ?? 0) > 0 && (
                        <> · held {money(Number(w.held_balance), w.currency)}</>
                      )}
                    </p>
                  </div>
                  <span className="tabular shrink-0 font-medium">
                    {money(Number(w.balance ?? 0), w.currency)}
                  </span>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div>
              <CardTitle>Recent movements</CardTitle>
              <CardDescription>The wallet ledger only.</CardDescription>
            </div>
            <Button asChild variant="ghost" size="sm">
              <Link to="/wallet/activity">Full activity</Link>
            </Button>
          </CardHeader>
          <CardContent className="pt-3">
            {txns.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : txns.isError ? (
              <ErrorState error={txns.error} onRetry={() => void txns.refetch()} />
            ) : (txns.data ?? []).length === 0 ? (
              <EmptyState title="Nothing has moved yet" />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Date</TH>
                      <TH>Movement</TH>
                      <TH className="text-right">Amount</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(txns.data ?? []).map((t) => {
                      const outbound = t.from_user_id === user?.id;
                      return (
                        <TR key={t.id}>
                          <TD className="whitespace-nowrap text-muted-foreground">
                            {shortDate(t.created_at)}
                          </TD>
                          <TD>
                            <Badge tone={outbound ? 'neutral' : 'success'}>
                              {outbound ? 'Sent' : 'Received'}
                            </Badge>
                          </TD>
                          <TD className="tabular whitespace-nowrap text-right">
                            {fmtToken(Number(t.amount), t.token_type)}
                          </TD>
                          <TD>
                            <StatusBadge status={t.status} />
                          </TD>
                        </TR>
                      );
                    })}
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
