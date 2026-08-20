import { toast } from 'sonner';
import { Banknote, Landmark, Link2, Loader2, Lock, Plus, Undo2 } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { maskIban, money, shortDate } from '@/lib/format';
import {
  useFiatWallets,
  useHeldTransfers,
  useIbanAccounts,
  useLinkIbanToPool,
  useRefundHeldTransfer,
} from './hooks';

/**
 * The accounts money settles through: cash wallets, IBANs, and anything the
 * treasury is currently holding.
 *
 * v2 showed held transfers on a page of their own, so a member whose payment
 * had been stopped saw their balance drop and nothing else. They belong beside
 * the balance they were taken from.
 */
export default function WalletAccounts() {
  return (
    <>
      <PageHeader
        title="Accounts"
        description="Cash wallets, bank accounts and funds the treasury is holding."
      />
      <div className="space-y-6">
        <HeldTransfersCard />
        <FiatWalletsCard />
        <IbanAccountsCard />
      </div>
    </>
  );
}

/* ---------------------------------------------------------------- held */

function HeldTransfersCard() {
  const held = useHeldTransfers();
  const refund = useRefundHeldTransfer();
  const rows = held.data ?? [];

  // Nothing held and nothing to report — do not take up space.
  if (!held.isLoading && !held.isError && rows.length === 0) return null;

  const claim = (txId: string) => {
    refund.mutate(txId, {
      onSuccess: (result) => toast.success(result.message ?? 'The transfer has been refunded.'),
      onError: (error: Error) => toast.error(error.message),
    });
  };

  return (
    <Card className="border-warning/30">
      <CardHeader>
        <div>
          <CardTitle>Held by the treasury</CardTitle>
          <CardDescription>
            These transfers were debited but never delivered. The funds return to your wallet once
            the hold expires.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="pt-3">
        {held.isLoading ? (
          <Skeleton className="h-24 w-full" />
        ) : held.isError ? (
          <ErrorState error={held.error} onRetry={() => void held.refetch()} />
        ) : (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>Reference</TH>
                  <TH>Recipient</TH>
                  <TH className="text-right">Amount</TH>
                  <TH>Held until</TH>
                  <TH className="text-right">Action</TH>
                </TR>
              </THead>
              <TBody>
                {rows.map((t) => {
                  const releaseAt = t.held_until ? new Date(t.held_until) : null;
                  const claimable = !releaseAt || releaseAt.getTime() <= Date.now();
                  // Only the row being refunded shows a spinner, not all of them.
                  const busy = refund.isPending && refund.variables === t.tx_id;
                  return (
                    <TR key={t.id}>
                      <TD className="font-mono text-xs">{t.tx_id}</TD>
                      <TD className="max-w-[16rem] truncate">{t.to_identifier}</TD>
                      <TD className="tabular whitespace-nowrap text-right font-medium">
                        {money(Number(t.amount), t.currency)}
                        {Number(t.fee ?? 0) > 0 && (
                          <span className="block text-xs font-normal text-muted-foreground">
                            fee {money(Number(t.fee), t.currency)}
                          </span>
                        )}
                      </TD>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(t.held_until)}
                      </TD>
                      <TD className="text-right">
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={!claimable || refund.isPending}
                          onClick={() => claim(t.tx_id)}
                          title={
                            claimable
                              ? undefined
                              : `Available from ${shortDate(t.held_until)}`
                          }
                        >
                          {busy ? <Loader2 className="animate-spin" /> : <Undo2 />}
                          Claim refund
                        </Button>
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
  );
}

/* ---------------------------------------------------------------- fiat */

function FiatWalletsCard() {
  const wallets = useFiatWallets();
  const rows = wallets.data ?? [];

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Cash wallets</CardTitle>
          <CardDescription>
            Available is the balance minus anything reserved against a pending transfer.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="pt-3">
        {wallets.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
          </div>
        ) : wallets.isError ? (
          <ErrorState error={wallets.error} onRetry={() => void wallets.refetch()} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Banknote className="size-5" />}
            title="No cash wallets"
            description="A wallet is opened automatically the first time funds settle to you in that currency."
          />
        ) : (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>Currency</TH>
                  <TH className="text-right">Balance</TH>
                  <TH className="text-right">Available</TH>
                  <TH className="text-right">Held</TH>
                  <TH>Updated</TH>
                </TR>
              </THead>
              <TBody>
                {rows.map((w) => (
                  <TR key={w.id}>
                    <TD className="font-medium">{w.currency}</TD>
                    <TD className="tabular text-right font-medium">
                      {money(Number(w.balance ?? 0), w.currency)}
                    </TD>
                    <TD className="tabular text-right">
                      {money(Number(w.available_balance ?? 0), w.currency)}
                    </TD>
                    <TD className="tabular text-right">
                      {Number(w.held_balance ?? 0) > 0 ? (
                        <span className="text-warning">
                          {money(Number(w.held_balance), w.currency)}
                        </span>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TD>
                    <TD className="whitespace-nowrap text-muted-foreground">
                      {shortDate(w.updated_at)}
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          </TableWrap>
        )}
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------------------- ibans */

function IbanAccountsCard() {
  const ibans = useIbanAccounts();
  const link = useLinkIbanToPool();
  const rows = ibans.data ?? [];

  const linkToPool = (ibanId: string) => {
    link.mutate(
      { ibanId, poolType: 'main' },
      {
        onSuccess: () => toast.success('Incoming funds on this account now route to your main pool.'),
        onError: (error: Error) => toast.error(error.message),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Bank accounts</CardTitle>
          <CardDescription>IBANs issued to you, and where their inbound funds land.</CardDescription>
        </div>
        {/* TODO(server): opening an account needs a `create_iban_for_user(p_user_id,
            p_country, p_currency, p_account_type)` RPC. v2 did this from the
            browser — it generated the IBAN client-side and inserted the row
            directly into `iban_accounts`, which lets any client mint itself a
            bank account with whatever holder name and country it likes. Until
            that function exists this stays disabled rather than being
            reimplemented. */}
        <Button size="sm" variant="secondary" disabled title="Not available yet — needs a server-side issuer">
          <Plus />
          Open an account
        </Button>
      </CardHeader>
      <CardContent className="pt-3">
        {ibans.isLoading ? (
          <div className="space-y-2">
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
          </div>
        ) : ibans.isError ? (
          <ErrorState error={ibans.error} onRetry={() => void ibans.refetch()} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Landmark className="size-5" />}
            title="No bank accounts"
            description="An IBAN is issued once your account review completes."
          />
        ) : (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>IBAN</TH>
                  <TH>Holder</TH>
                  <TH>Type</TH>
                  <TH className="text-right">Balance</TH>
                  <TH>Status</TH>
                  <TH className="text-right">Action</TH>
                </TR>
              </THead>
              <TBody>
                {rows.map((a) => {
                  const busy = link.isPending && link.variables?.ibanId === a.id;
                  return (
                  <TR key={a.id}>
                    <TD>
                      <span className="font-mono text-sm">{maskIban(a.iban)}</span>
                      {a.is_data_encrypted && (
                        <Badge tone="info" className="ml-2">
                          <Lock className="size-3" />
                          Encrypted
                        </Badge>
                      )}
                      <p className="text-xs text-muted-foreground">
                        {a.country_code} · {a.bic === '***ENCRYPTED***' ? 'BIC encrypted' : a.bic}
                      </p>
                    </TD>
                    <TD className="max-w-[14rem] truncate">{a.account_holder}</TD>
                    <TD className="capitalize text-muted-foreground">
                      {a.account_type.replace(/_/g, ' ')}
                    </TD>
                    <TD className="tabular whitespace-nowrap text-right font-medium">
                      {money(Number(a.balance ?? 0), a.currency)}
                    </TD>
                    <TD>
                      <StatusBadge status={a.status ?? 'active'} />
                    </TD>
                    <TD className="text-right">
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => linkToPool(a.id)}
                        disabled={link.isPending}
                        aria-label={`Route incoming funds on ${maskIban(a.iban)} to your main pool`}
                      >
                        {busy ? <Loader2 className="animate-spin" /> : <Link2 />}
                        Link to pool
                      </Button>
                    </TD>
                  </TR>
                  );
                })}
              </TBody>
            </Table>
          </TableWrap>
        )}

        {rows.some((a) => a.is_data_encrypted) && (
          <p className="pt-4 text-xs text-muted-foreground">
            Encrypted accounts are stored with their IBAN and BIC sealed. They are shown masked here
            because decryption happens server-side; v2 rendered the literal placeholder
            <code className="mx-1 font-mono">***ENCRYPTED***</code> into the copy button and the
            share dialog.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
