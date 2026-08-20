import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Banknote, Landmark, Link2, Loader2, Lock, Plus, Send, Undo2, X } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input, Label } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { maskIban, money, shortDate } from '@/lib/format';
import { useAuth } from '@/features/auth/AuthProvider';
import {
  IBAN_ACCOUNT_TYPES,
  IBAN_CURRENCIES,
  useFiatWallets,
  useHeldTransfers,
  useIbanAccounts,
  useIbanRequests,
  useLinkIbanToPool,
  useRefundHeldTransfer,
  useRequestIbanAccount,
  type IbanAccountType,
  type IbanCurrency,
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
  const requests = useIbanRequests();
  const [formOpen, setFormOpen] = useState(false);
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
        {/*
          Opening an account is a REQUEST, not an instant issue, and the reason
          is stated on screen rather than hidden here.

          An IBAN must be unique and mod-97 correct, so the browser must not
          invent one — and v2 did exactly that, generating the number in the
          page and inserting straight into `iban_accounts`. That policy is still
          open, so this screen deliberately does not use it.

          TODO(server): `create_iban_for_user` and `create_ccoin_iban_for_user`
          both exist and both fail on every call (23502 for the missing NOT NULL
          `account_holder`/`account_type`; P0001 for the encryption trigger
          ordering; PGRST203 for the ambiguous overload). Repair one of them,
          drop `p_user_id` in favour of `auth.uid()`, and this button can issue
          directly instead of raising a ticket. See F-071/F-072.
        */}
        <Button
          size="sm"
          variant={formOpen ? 'ghost' : 'secondary'}
          onClick={() => setFormOpen((open) => !open)}
          aria-expanded={formOpen}
          aria-controls="iban-request-form"
        >
          {formOpen ? <X /> : <Plus />}
          {formOpen ? 'Cancel' : 'Request an account'}
        </Button>
      </CardHeader>

      {formOpen && (
        <CardContent className="border-b border-border pb-6 pt-0">
          <IbanRequestForm
            heldCurrencies={rows.map((a) => a.currency)}
            onDone={() => setFormOpen(false)}
          />
        </CardContent>
      )}
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
            description="Request one above. An operator issues the IBAN — it is not generated here."
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

        <IbanRequestList query={requests} />

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

/* ------------------------------------------------------- account requests */

/**
 * Ask an operator to open an account.
 *
 * Nothing here decides a number. The member chooses a currency, a type and the
 * name the account is held in; the IBAN, the BIC and the balance are the
 * server's to write. The form says so plainly rather than implying an instant
 * issue, because there is nothing instant behind it.
 *
 * One account per currency is not a UI preference either — `iban_accounts` has
 * `UNIQUE (user_id, currency)`, so a currency the member already holds is
 * disabled with the reason rather than offered and then refused by a 23505.
 */
function IbanRequestForm({
  heldCurrencies,
  onDone,
}: {
  heldCurrencies: string[];
  onDone: () => void;
}) {
  const { user } = useAuth();
  const request = useRequestIbanAccount();

  const held = useMemo(() => new Set(heldCurrencies), [heldCurrencies]);
  const firstFree = IBAN_CURRENCIES.find((c) => !held.has(c.currency));

  const [currency, setCurrency] = useState<IbanCurrency>(
    firstFree?.currency ?? IBAN_CURRENCIES[0].currency
  );
  const [accountType, setAccountType] = useState<IbanAccountType>('personal');
  const [holder, setHolder] = useState('');

  const metaName = user?.user_metadata?.full_name;
  useEffect(() => {
    if (typeof metaName === 'string' && metaName.trim()) {
      setHolder((current) => current || metaName.trim());
    }
  }, [metaName]);

  const selected = IBAN_CURRENCIES.find((c) => c.currency === currency) ?? IBAN_CURRENCIES[0];
  const alreadyHeld = held.has(currency);
  const holderValid = holder.trim().length > 1;
  const canSubmit = holderValid && !alreadyHeld && !!user?.email && !request.isPending;

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (!canSubmit) return;
    request.mutate(
      {
        currency,
        country: selected.country,
        accountType,
        accountHolder: holder.trim(),
      },
      {
        onSuccess: () => {
          toast.success('Request sent', {
            description: 'It is now in the operations queue. You can follow it below.',
          });
          setHolder('');
          onDone();
        },
        onError: (error: Error) =>
          toast.error('The request was not sent', { description: error.message }),
      }
    );
  };

  return (
    <form id="iban-request-form" className="space-y-4" onSubmit={submit}>
      <div className="rounded-lg border border-info/20 bg-info/10 p-3 text-sm text-muted-foreground">
        An IBAN is issued by the bank, not by this page. Sending this raises a request an operator
        reviews and fulfils; no account exists and no number is reserved until they do.
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="space-y-1.5">
          <Label htmlFor="iban-currency">Currency</Label>
          <select
            id="iban-currency"
            value={currency}
            onChange={(event) => setCurrency(event.target.value as IbanCurrency)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground"
          >
            {IBAN_CURRENCIES.map((option) => (
              <option key={option.currency} value={option.currency}>
                {option.label}
                {held.has(option.currency) ? ' — already held' : ''}
              </option>
            ))}
          </select>
          <p className="text-xs text-muted-foreground">
            {alreadyHeld
              ? 'You already hold an account in this currency. One account per currency is allowed.'
              : `Issued in ${selected.country}.`}
          </p>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="iban-type">Account type</Label>
          <select
            id="iban-type"
            value={accountType}
            onChange={(event) => setAccountType(event.target.value as IbanAccountType)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground"
          >
            {IBAN_ACCOUNT_TYPES.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </div>

        <Field
          label="Account holder"
          htmlFor="iban-holder"
          error={holder.length > 0 && !holderValid ? 'Enter the full name.' : undefined}
          hint="The name the account is opened in."
        >
          <Input
            id="iban-holder"
            value={holder}
            onChange={(event) => setHolder(event.target.value)}
            autoComplete="name"
            aria-invalid={holder.length > 0 && !holderValid}
          />
        </Field>
      </div>

      {!user?.email && (
        <p className="text-sm text-danger">
          Your account has no email address, so an operator would have nowhere to reply. Add one
          before requesting an account.
        </p>
      )}

      <Button type="submit" size="sm" disabled={!canSubmit}>
        {request.isPending ? <Loader2 className="animate-spin" /> : <Send />}
        Send request
      </Button>
    </form>
  );
}

/**
 * The member's own requests, and where each one stands.
 *
 * A submit with no visible result is not finished: after sending, the request
 * lands here with its status, so "did that do anything" has an answer on the
 * same screen. Loading, error and empty are three different messages.
 */
function IbanRequestList({
  query,
}: {
  query: ReturnType<typeof useIbanRequests>;
}) {
  const rows = query.data ?? [];

  if (query.isLoading) {
    return (
      <div className="pt-6">
        <Skeleton className="h-16 w-full" />
      </div>
    );
  }

  if (query.isError) {
    return (
      <div className="pt-6">
        <ErrorState
          title="Could not load your account requests"
          error={query.error}
          onRetry={() => void query.refetch()}
        />
      </div>
    );
  }

  if (rows.length === 0) return null;

  return (
    <div className="pt-6">
      <h3 className="mb-2 text-sm font-semibold">Account requests</h3>
      <p className="mb-3 text-xs text-muted-foreground">
        Requests you have sent. An operator issues the IBAN; until then nothing is reserved.
      </p>
      <TableWrap>
        <Table>
          <THead>
            <TR>
              <TH>Sent</TH>
              <TH>Request</TH>
              <TH>Status</TH>
              <TH>Closed</TH>
            </TR>
          </THead>
          <TBody>
            {rows.map((r) => (
              <TR key={r.id}>
                <TD className="whitespace-nowrap text-muted-foreground">{shortDate(r.created_at)}</TD>
                <TD className="max-w-[28rem]">{r.error_details}</TD>
                <TD>
                  <StatusBadge status={r.status} />
                </TD>
                <TD className="whitespace-nowrap text-muted-foreground">
                  {r.resolved_at ? shortDate(r.resolved_at) : '—'}
                </TD>
              </TR>
            ))}
          </TBody>
        </Table>
      </TableWrap>
    </div>
  );
}
