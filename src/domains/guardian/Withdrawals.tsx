import { useMemo, useState, type SelectHTMLAttributes } from 'react';
import { toast } from 'sonner';
import {
  ArrowUpFromLine,
  Ban,
  CheckCircle2,
  Loader2,
  Send,
  Timer,
  XCircle,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { token as fmtToken, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { hoursUntil, LockedAction, shortAddress } from './shared';
import { useGuardianWallets, useRequestWithdrawal, useWithdrawalRequests } from './hooks';

/** Native select styled to match Input, so forms need no popover library. */
function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        'flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground transition-colors',
        'disabled:cursor-not-allowed disabled:opacity-50',
        className
      )}
      {...props}
    />
  );
}

const PENDING_STATUSES = new Set(['pending', 'processing', 'approved']);

/**
 * Withdrawal requests against the vault.
 *
 * The division of labour here is the whole point of the screen. Asking for a
 * withdrawal is a client write, because it moves nothing — it books a row that
 * RLS forces to carry the caller's own `user_id`. Every transition after that
 * (approve, complete, reject, cancel) is a treasury decision that has to happen
 * next to the payout itself, in one server-side transaction that broadcasts the
 * transfer and records the hash the chain returns.
 *
 * No such routine exists today, so those controls are rendered disabled with
 * the reason on screen. v2 wired all of them to
 * `guardian_withdrawal_requests.update({ status })` from the browser and
 * followed each with a success toast: "Withdrawal approved" appeared, the row
 * turned green, and not one satoshi had moved. Its member-facing cancel button
 * was worse still — the table has no owner UPDATE policy, so PostgREST filtered
 * the update to zero rows and returned success, and the toast fired on a write
 * the database had refused.
 */
export default function Withdrawals() {
  const requests = useWithdrawalRequests();

  const rows = requests.data ?? [];
  const open = rows.filter((r) => PENDING_STATUSES.has(r.status));
  const openTotalByAsset = useMemo(() => {
    const seen = new Set(open.map((r) => r.asset_symbol));
    return seen.size;
  }, [open]);

  return (
    <>
      <PageHeader
        title="Withdrawals"
        description="Requests to move assets out of the vault, and where each one stands."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <Stat
          label="Open requests"
          value={String(open.length)}
          sub={`Across ${openTotalByAsset} asset${openTotalByAsset === 1 ? '' : 's'}`}
          tone={open.length > 0 ? 'warning' : 'default'}
          icon={<Timer className="size-4" />}
          loading={requests.isLoading}
        />
        <Stat
          label="Completed"
          value={String(rows.filter((r) => r.status === 'completed').length)}
          sub="Settled and recorded"
          tone="success"
          icon={<CheckCircle2 className="size-4" />}
          loading={requests.isLoading}
        />
        <Stat
          label="Rejected or cancelled"
          value={String(rows.filter((r) => r.status === 'rejected' || r.status === 'cancelled').length)}
          sub="Closed without a payout"
          icon={<XCircle className="size-4" />}
          loading={requests.isLoading}
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)]">
        <RequestCard />

        <Card>
          <CardHeader>
            <div>
              <CardTitle>Requests</CardTitle>
              <CardDescription>
                Every request you are permitted to see. A 96-hour processing window applies from the
                moment one is booked.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="pt-3">
            {requests.isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-10 w-full" />
              </div>
            ) : requests.isError ? (
              <ErrorState
                title="Could not load withdrawal requests"
                error={requests.error}
                onRetry={() => void requests.refetch()}
              />
            ) : rows.length === 0 ? (
              <EmptyState
                icon={<ArrowUpFromLine className="size-5" />}
                title="No withdrawal requests"
                description="Requests you book, and any you are permitted to review, appear here."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Requested</TH>
                      <TH className="text-right">Amount</TH>
                      <TH>Destination</TH>
                      <TH>Window</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {rows.map((r) => {
                      const left = hoursUntil(r.window_expires_at);
                      return (
                        <TR key={r.id}>
                          <TD className="whitespace-nowrap text-muted-foreground">
                            {shortDate(r.requested_at)}
                          </TD>
                          <TD className="tabular whitespace-nowrap text-right font-medium">
                            {fmtToken(Number(r.amount), r.asset_symbol)}
                          </TD>
                          <TD>
                            <p className="font-mono text-xs">{shortAddress(r.destination_address)}</p>
                            <p className="text-xs text-muted-foreground">{r.network}</p>
                          </TD>
                          <TD className="whitespace-nowrap text-xs">
                            {r.status === 'pending' && left !== null ? (
                              <span className={left === 0 ? 'text-danger' : 'text-warning'}>
                                {left}h remaining
                              </span>
                            ) : r.processed_at ? (
                              <span className="text-muted-foreground">
                                Actioned {shortDate(r.processed_at)}
                              </span>
                            ) : (
                              <span className="text-muted-foreground">—</span>
                            )}
                          </TD>
                          <TD>
                            <StatusBadge status={r.status} />
                            {r.admin_notes && (
                              <p className="mt-1 max-w-[16rem] text-xs text-muted-foreground">
                                {r.admin_notes}
                              </p>
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
      </div>

      {open.length > 0 && <DecisionQueue count={open.length} />}
    </>
  );
}

/* ---------------------------------------------------------------- request */

function RequestCard() {
  const wallets = useGuardianWallets();
  const request = useRequestWithdrawal();

  const options = wallets.data ?? [];
  const [walletId, setWalletId] = useState('');
  const [destination, setDestination] = useState('');
  const [amount, setAmount] = useState('');

  const selected = options.find((w) => w.id === walletId) ?? null;
  const amountNum = Number(amount);
  const recorded = Number(selected?.balance ?? 0);

  const amountError =
    amount && (!Number.isFinite(amountNum) || amountNum <= 0)
      ? 'Enter an amount greater than zero.'
      : selected && amountNum > recorded
        ? `More than the vault records for this wallet (${fmtToken(recorded, selected.asset_symbol)}).`
        : undefined;

  const destinationError =
    destination && destination.trim().length < 20
      ? 'That does not look like a full destination address.'
      : undefined;

  const blocked =
    !selected ||
    !destination.trim() ||
    !amount ||
    !!amountError ||
    !!destinationError ||
    request.isPending;

  const submit = () => {
    if (!selected) return;
    request.mutate(
      {
        walletId: selected.id,
        assetSymbol: selected.asset_symbol,
        network: selected.network,
        amount: amountNum,
        destinationAddress: destination.trim(),
      },
      {
        onSuccess: () => {
          toast.success('Withdrawal requested.', {
            description: 'A 96-hour processing window applies before it can be actioned.',
          });
          setDestination('');
          setAmount('');
        },
        onError: (error: Error) => toast.error(error.message),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Request a withdrawal</CardTitle>
          <CardDescription>
            This books a request. It does not move anything — the amount below is checked against
            the balance the vault records, and the server checks it again before any payout.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-4 pt-3">
        {wallets.isLoading ? (
          <>
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-9 w-full" />
          </>
        ) : wallets.isError ? (
          <ErrorState error={wallets.error} onRetry={() => void wallets.refetch()} />
        ) : options.length === 0 ? (
          <EmptyState
            title="No wallet to withdraw from"
            description="Guardian wallets are opened by an operator. Nothing is created by visiting this page."
          />
        ) : (
          <>
            <Field label="From wallet" htmlFor="gw-wallet">
              <Select
                id="gw-wallet"
                value={walletId}
                onChange={(event) => setWalletId(event.target.value)}
              >
                <option value="">Select a wallet</option>
                {options.map((w) => (
                  <option key={w.id} value={w.id}>
                    {w.asset_symbol} · {w.network} · {fmtToken(Number(w.balance ?? 0), w.asset_symbol)}
                  </option>
                ))}
              </Select>
            </Field>

            <Field
              label="Destination address"
              htmlFor="gw-destination"
              error={destinationError}
              hint={selected ? `Must be a valid ${selected.network} address.` : undefined}
            >
              <Input
                id="gw-destination"
                value={destination}
                onChange={(event) => setDestination(event.target.value)}
                aria-invalid={!!destinationError}
                placeholder="Paste the receiving address"
                autoComplete="off"
                spellCheck={false}
              />
            </Field>

            <Field label="Amount" htmlFor="gw-amount" error={amountError}>
              <Input
                id="gw-amount"
                type="number"
                min="0"
                step="any"
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                aria-invalid={!!amountError}
                placeholder="0.00"
              />
            </Field>

            <Button type="button" className="w-full" disabled={blocked} onClick={submit}>
              {request.isPending ? <Loader2 className="animate-spin" /> : <Send />}
              Request withdrawal
            </Button>

            {/*
              TODO(server): cancelling a booked request needs a
              `guardian-cancel-withdrawal` edge function. The table carries no
              owner UPDATE policy — only `Admins can manage all withdrawals` —
              so a client-side `update({ status: 'cancelled' })` is filtered to
              zero rows by RLS and returns success with an empty result. v2
              cancelled that way and toasted on it, then patched its local state
              so the row looked cancelled until the next reload.
            */}
            <LockedAction
              icon={<Ban aria-hidden="true" />}
              label="Cancel a request"
              reason="Cancelling releases a reserved amount, so it is a server-side operation. The database grants no owner update on this table, and a write it silently drops must not be reported as a success."
            />
          </>
        )}
      </CardContent>
    </Card>
  );
}

/* ------------------------------------------------------------- decisions */

/**
 * The operator side of the queue.
 *
 * Rendered as a panel rather than per-row buttons because there is nothing to
 * click yet: every decision on this queue is blocked on a server routine that
 * does not exist. Saying so once, plainly, is more honest than putting three
 * disabled buttons on each of forty rows.
 */
function DecisionQueue({ count }: { count: number }) {
  return (
    <Card className="mt-6">
      <CardHeader>
        <div>
          <CardTitle>Decisions</CardTitle>
          <CardDescription>
            {count} request{count === 1 ? '' : 's'} awaiting an outcome.
          </CardDescription>
        </div>
        <Badge tone="warning">Server routine required</Badge>
      </CardHeader>
      <CardContent className="space-y-4 pt-3">
        <p className="text-sm text-muted-foreground">
          Approving, completing or rejecting a request are all treasury actions: they release funds,
          or release a reservation, and the record has to be written in the same transaction that
          performs the transfer, with the hash the chain actually returned. A browser cannot do
          either half of that, so none of these controls is wired to a table update.
        </p>

        {/*
          TODO(server): all three actions below need one edge function —
          `guardian-process-withdrawal` — taking the request id and a decision,
          and doing the work server-side under the caller's JWT:

            approve  → re-check the request is still pending and inside its
                       window, reserve the amount against the guardian wallet,
                       set status = 'approved', processed_by = the id from the
                       token (never a field the client supplied).
            complete → broadcast the payout, store the returned tx_hash on a
                       guardian_transactions row, then set status = 'completed'.
                       A completion without a hash is a claim, not a settlement.
            reject   → release the reservation and record the reason.

          Until it exists these stay disabled. v2 performed all three as direct
          `update({ status })` calls from the browser (AdminAresGuardian.tsx
          updateStatus) and never checked the result, so a row RLS refused to
          update still produced "Withdrawal approved".
        */}
        <div className="space-y-3">
          <LockedAction
            icon={<CheckCircle2 aria-hidden="true" />}
            label="Approve"
            reason="Approval reserves funds against the vault; it must be booked by the server that performs the reservation."
          />
          <LockedAction
            icon={<ArrowUpFromLine aria-hidden="true" />}
            label="Mark as sent"
            reason="A completed withdrawal has to carry the transaction hash the chain returned. The browser never sees one, so it cannot record a settlement."
          />
          <LockedAction
            icon={<XCircle aria-hidden="true" />}
            label="Reject"
            reason="Rejection releases the reservation the request holds, which is the same server-side operation in reverse."
          />
        </div>
      </CardContent>
    </Card>
  );
}
