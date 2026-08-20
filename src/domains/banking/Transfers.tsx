import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { ArrowLeftRight, Coins, Info, Loader2 } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, token, shortDate } from '@/lib/format';
import {
  useBankApplication,
  useBankingProfile,
  useConvertWstrToFiat,
  useCrossBorderPayments,
  useFiatTransactions,
  usePendingTreasuryTransfers,
  useSubmitSwap,
} from './hooks';
import { AsyncSection, ApprovalGate, SelectInput, ServerActionPending } from './shared';

const FIAT = ['EUR', 'USD', 'CHF', 'GBP'] as const;
const CRYPTO = ['STR', 'wSTR', 'BTC', 'ETH', 'CCOS'] as const;
const SWAPPABLE = [...FIAT, ...CRYPTO];

/**
 * Indicative rates only, mirroring the table inside submit-bank-swap so the
 * preview does not contradict the receipt. The server prices the swap; nothing
 * here is authoritative and the UI says so.
 */
const EUR_RATES: Record<string, number> = {
  EUR: 1,
  USD: 0.92,
  CHF: 1.05,
  GBP: 1.17,
  STR: 0.0094,
  wSTR: 0.0106,
  BTC: 62000,
  ETH: 3200,
  CCOS: 9.35,
};

function isFiat(currency: string) {
  return (FIAT as readonly string[]).includes(currency);
}

/** Fiat gets a currency symbol; a token is not a currency and must not get one. */
function amount(value: number, currency: string) {
  return isFiat(currency) ? money(value, currency) : token(value, currency);
}

function previewAmount(value: number, from: string, to: string) {
  const inEur = value * (EUR_RATES[from] ?? 0);
  const perUnit = EUR_RATES[to] ?? 0;
  return perUnit ? inEur / perUnit : 0;
}

function errorMessage(err: unknown, fallback: string) {
  return err instanceof Error ? err.message : fallback;
}

export default function Transfers() {
  const application = useBankApplication();
  const profile = useBankingProfile();
  const pending = usePendingTreasuryTransfers();
  const history = useFiatTransactions(20);
  const crossBorder = useCrossBorderPayments(10);

  const swap = useSubmitSwap();
  const convert = useConvertWstrToFiat();

  const [fromCurrency, setFromCurrency] = useState('EUR');
  const [toCurrency, setToCurrency] = useState('USD');
  const [swapAmount, setSwapAmount] = useState('');
  const [wstrAmount, setWstrAmount] = useState('');
  const [wstrTarget, setWstrTarget] = useState('EUR');

  const gateLoading = application.isLoading || profile.isLoading;
  const approved = application.data?.status === 'approved' || !!profile.data;

  const swapValue = Number(swapAmount) || 0;
  const quote = useMemo(
    () => previewAmount(swapValue, fromCurrency, toCurrency),
    [swapValue, fromCurrency, toCurrency]
  );

  // Crypto out to fiat travels a different rail and carries a higher CCOS fee.
  const rail = !isFiat(fromCurrency) && isFiat(toCurrency) ? 'swap_crypto' : 'swap_fiat';
  const indicativeFee = rail === 'swap_crypto' ? 1.0 : 0.3;

  async function submitSwap() {
    if (fromCurrency === toCurrency) {
      toast.error('Choose two different currencies.');
      return;
    }
    if (!Number.isFinite(swapValue) || swapValue <= 0) {
      toast.error('Enter an amount greater than zero.');
      return;
    }

    try {
      const result = await swap.mutateAsync({ fromCurrency, toCurrency, amount: swapValue });
      toast.success('Swap submitted for approval.', {
        description:
          amount(swapValue, fromCurrency) +
          ' to ' +
          amount(Number(result.to_amount ?? quote), toCurrency) +
          ' · CCOS fee ' +
          String(result.fee?.fee_ccos ?? indicativeFee),
      });
      setSwapAmount('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not submit the swap'));
    }
  }

  async function submitConversion() {
    const value = Number(wstrAmount);
    if (!Number.isFinite(value) || value <= 0) {
      toast.error('Enter a wSTR amount greater than zero.');
      return;
    }

    try {
      const result = await convert.mutateAsync({ wstrAmount: value, targetCurrency: wstrTarget });
      toast.success('wSTR converted.', {
        description: money(Number(result.fiat_amount ?? 0), result.currency ?? wstrTarget),
      });
      setWstrAmount('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not convert wSTR'));
    }
  }

  return (
    <>
      <PageHeader
        title="Transfers"
        description="Swap between rails, convert wSTR to fiat and follow every movement."
      />

      {gateLoading ? (
        <Skeleton className="h-48 w-full" />
      ) : !approved ? (
        <ApprovalGate status={application.data?.status} />
      ) : (
        <div className="space-y-6">
          <div className="grid gap-6 lg:grid-cols-2">
            {/* Swap */}
            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle className="flex items-center gap-2">
                    <ArrowLeftRight className="size-4 text-primary" />
                    Swap
                  </CardTitle>
                  <CardDescription>
                    Fiat FX and crypto to fiat. Submitted as pending; a CCOS fee is captured on
                    submission and routed to the bank liquidity pool.
                  </CardDescription>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="From" htmlFor="swap-from">
                    <SelectInput
                      id="swap-from"
                      value={fromCurrency}
                      onChange={(e) => setFromCurrency(e.target.value)}
                    >
                      {SWAPPABLE.map((c) => (
                        <option key={c} value={c}>
                          {c}
                        </option>
                      ))}
                    </SelectInput>
                  </Field>
                  <Field label="To" htmlFor="swap-to">
                    <SelectInput
                      id="swap-to"
                      value={toCurrency}
                      onChange={(e) => setToCurrency(e.target.value)}
                    >
                      {SWAPPABLE.map((c) => (
                        <option key={c} value={c}>
                          {c}
                        </option>
                      ))}
                    </SelectInput>
                  </Field>
                </div>

                <Field label={'Amount (' + fromCurrency + ')'} htmlFor="swap-amount">
                  <Input
                    id="swap-amount"
                    type="number"
                    min="0"
                    step="0.0001"
                    placeholder="0.00"
                    value={swapAmount}
                    onChange={(e) => setSwapAmount(e.target.value)}
                  />
                </Field>

                <div className="space-y-2 rounded-lg border border-border p-3 text-sm">
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">You send</span>
                    <span className="tabular">{amount(swapValue, fromCurrency)}</span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">You receive (indicative)</span>
                    <span className="tabular">{amount(quote, toCurrency)}</span>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">Rail</span>
                    <Badge tone="neutral">{rail}</Badge>
                  </div>
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-muted-foreground">CCOS fee</span>
                    <span className="tabular text-warning">{token(indicativeFee, 'ccos')}</span>
                  </div>
                </div>

                <p className="flex items-start gap-2 text-xs text-muted-foreground">
                  <Info className="mt-0.5 size-3.5 shrink-0" />
                  The rate above is indicative. submit-bank-swap prices the swap, captures the fee
                  and holds the funds — if your CCOS balance is short the fee is sourced from STR,
                  then wSTR, then fiat.
                </p>

                <Button
                  className="w-full"
                  onClick={() => void submitSwap()}
                  disabled={swap.isPending}
                >
                  {swap.isPending ? <Loader2 className="animate-spin" /> : <ArrowLeftRight />}
                  Submit swap
                </Button>
              </CardContent>
            </Card>

            {/* wSTR conversion and unavailable rails */}
            <div className="space-y-6">
              <Card>
                <CardHeader>
                  <div className="space-y-1">
                    <CardTitle className="flex items-center gap-2">
                      <Coins className="size-4 text-primary" />
                      Convert wSTR to fiat
                    </CardTitle>
                    <CardDescription>
                      Priced and settled by convert-wstr-to-fiat against the live wSTR rate.
                    </CardDescription>
                  </div>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="grid gap-4 sm:grid-cols-2">
                    <Field label="wSTR amount" htmlFor="wstr-amount">
                      <Input
                        id="wstr-amount"
                        type="number"
                        min="0"
                        step="0.0001"
                        placeholder="0.0000"
                        value={wstrAmount}
                        onChange={(e) => setWstrAmount(e.target.value)}
                      />
                    </Field>
                    <Field label="Receive in" htmlFor="wstr-target">
                      <SelectInput
                        id="wstr-target"
                        value={wstrTarget}
                        onChange={(e) => setWstrTarget(e.target.value)}
                      >
                        {FIAT.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </SelectInput>
                    </Field>
                  </div>

                  <Button
                    className="w-full"
                    onClick={() => void submitConversion()}
                    disabled={convert.isPending}
                  >
                    {convert.isPending ? <Loader2 className="animate-spin" /> : <Coins />}
                    Convert
                  </Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <div className="space-y-1">
                    <CardTitle>Outbound payments</CardTitle>
                    <CardDescription>
                      Awaiting a server-side path before they can be offered here.
                    </CardDescription>
                  </div>
                </CardHeader>
                <CardContent className="space-y-3">
                  <ServerActionPending
                    label="Send money to another member"
                    todo="Needs process-fiat-transfer (recipient resolution, balance debit, treasury hold and CCOS fee capture). It is not among the functions this domain is cleared to call, so the form is not offered — a client-side fiat_wallets update would let a member spend a balance they do not have."
                  />
                  <ServerActionPending
                    label="SEPA / SWIFT payout to an external bank"
                    todo="Needs a payout function that runs sanctions and compliance screening, prices the rail and writes the cross_border_payments row. cross_border_payments is read-only in this app for that reason."
                  />
                  <ServerActionPending
                    label="Request a refund on a held transfer"
                    todo="Needs request-transfer-refund. Reversing a treasury hold must be authorised and audited server-side."
                  />
                </CardContent>
              </Card>
            </div>
          </div>

          {/* Pending */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Held in treasury</CardTitle>
                <CardDescription>
                  Submitted movements waiting on an administrator. The CCOS fee is already captured.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={pending}
                emptyTitle="Nothing held"
                emptyDescription="Submitted transfers and swaps appear here until they are released."
                skeletonClassName="mx-5 h-32"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Submitted</TH>
                          <TH>Rail</TH>
                          <TH>Destination</TH>
                          <TH className="text-right">Amount</TH>
                          <TH className="text-right">CCOS fee</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((row) => (
                          <TR key={row.id}>
                            <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                            <TD className="font-medium uppercase">
                              {row.rail ?? row.transfer_type}
                            </TD>
                            <TD className="max-w-[14rem] truncate font-mono text-xs">
                              {row.to_identifier}
                            </TD>
                            <TD className="tabular text-right">
                              {money(Number(row.amount), row.currency)}
                            </TD>
                            <TD className="tabular text-right text-warning">
                              {token(Number(row.fee_ccos ?? 0), 'ccos')}
                            </TD>
                            <TD>
                              <StatusBadge status={row.status} />
                            </TD>
                          </TR>
                        ))}
                      </TBody>
                    </Table>
                  </TableWrap>
                )}
              </AsyncSection>
            </CardContent>
          </Card>

          {/* History */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Fiat movements</CardTitle>
                <CardDescription>Settled and in-flight transfers on this profile.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={history}
                emptyTitle="No movements yet"
                emptyDescription="Transfers in and out of your accounts appear here."
                skeletonClassName="mx-5 h-40"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Date</TH>
                          <TH>Type</TH>
                          <TH>From</TH>
                          <TH>To</TH>
                          <TH className="text-right">Amount</TH>
                          <TH className="text-right">Fee</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((row) => (
                          <TR key={row.id}>
                            <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                            <TD className="capitalize">{row.transfer_type}</TD>
                            <TD className="max-w-[10rem] truncate font-mono text-xs">
                              {row.from_identifier}
                            </TD>
                            <TD className="max-w-[10rem] truncate font-mono text-xs">
                              {row.to_identifier}
                            </TD>
                            <TD className="tabular text-right">
                              {money(Number(row.amount), row.currency)}
                            </TD>
                            <TD className="tabular text-right text-muted-foreground">
                              {money(Number(row.fee ?? 0), row.currency)}
                            </TD>
                            <TD>
                              <StatusBadge status={row.status} />
                            </TD>
                          </TR>
                        ))}
                      </TBody>
                    </Table>
                  </TableWrap>
                )}
              </AsyncSection>
            </CardContent>
          </Card>

          {/* Cross-border */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Cross-border payments</CardTitle>
                <CardDescription>
                  Payments routed over an international rail, with their compliance score.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={crossBorder}
                emptyTitle="No cross-border payments"
                emptyDescription="International payouts appear here once a payout rail is enabled."
                skeletonClassName="mx-5 h-32"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Date</TH>
                          <TH>Rail</TH>
                          <TH>Recipient</TH>
                          <TH>Route</TH>
                          <TH className="text-right">Amount</TH>
                          <TH className="text-right">Compliance</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((row) => (
                          <TR key={row.id}>
                            <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                            <TD className="uppercase">{row.payment_rail}</TD>
                            <TD>{row.recipient_name ?? '—'}</TD>
                            <TD className="text-muted-foreground">
                              {(row.sender_country ?? '—') + ' → ' + (row.receiver_country ?? '—')}
                            </TD>
                            <TD className="tabular text-right">
                              {money(Number(row.amount), row.currency)}
                            </TD>
                            <TD className="tabular text-right">
                              {row.compliance_score === null ? '—' : row.compliance_score}
                            </TD>
                            <TD>
                              <StatusBadge status={row.status} />
                            </TD>
                          </TR>
                        ))}
                      </TBody>
                    </Table>
                  </TableWrap>
                )}
              </AsyncSection>
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
