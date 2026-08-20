import { useMemo, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Ticket } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate, token } from '@/lib/format';
import { useAuth } from '@/features/auth/AuthProvider';
import { VOUCHER_PACKAGES, VOUCHER_PAYMENT_TYPES, VOUCHER_TOKEN_TYPES } from './constants';
import { Async, Section } from './shared';
import { useMyVouchers, useRedeemVoucher } from './hooks';

/**
 * Voucher claims and what they were credited.
 *
 * The form below writes a pending claim and nothing else. The token amount is
 * decided by the server against its own package table when the claim is
 * reviewed, which is why the member picks a package rather than typing an
 * amount: an amount typed here would be a number the browser chose.
 */
export default function VouchersPage() {
  const vouchers = useMyVouchers();

  const credited = (vouchers.data?.redemptions ?? [])
    .filter((v) => v.tokens_credited)
    .reduce((sum, v) => sum + Number(v.credited_amount ?? 0), 0);
  const pending = (vouchers.data?.redemptions ?? []).filter((v) => v.status === 'pending').length;

  return (
    <>
      <PageHeader
        title="Vouchers"
        description="Claim a voucher and follow what it was credited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Claims"
          value={String(vouchers.data?.redemptions.length ?? 0)}
          loading={vouchers.isLoading}
          icon={<Ticket className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Awaiting review"
          value={String(pending)}
          loading={vouchers.isLoading}
          tone={pending > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Credited"
          value={credited.toLocaleString('en-IE')}
          sub="Tokens released to your pools"
          loading={vouchers.isLoading}
          tone="success"
        />
      </div>

      <div className="space-y-6">
        <RedeemForm />

        <Section title="Your claims" bodyClassName="p-0 pt-0">
          <Async
            query={vouchers}
            isEmpty={(d) => d.redemptions.length === 0}
            emptyTitle="No voucher claims"
            emptyDescription="Claims you submit will be listed here with their review status."
            skeleton={
              <div className="p-5">
                <Skeleton className="h-32 w-full" />
              </div>
            }
          >
            {(data) => (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Package</TH>
                      <TH>Token</TH>
                      <TH>Paid by</TH>
                      <TH className="text-right">Credited</TH>
                      <TH>Claimed</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {data.redemptions.map((v) => (
                      <TR key={v.id}>
                        <TD className="max-w-64 truncate font-medium">{v.package_type}</TD>
                        <TD className="uppercase text-muted-foreground">{v.token_type}</TD>
                        <TD className="capitalize text-muted-foreground">{v.payment_type}</TD>
                        <TD className="tabular text-right">
                          {v.tokens_credited ? (
                            token(v.credited_amount, v.token_type)
                          ) : (
                            <span className="text-muted-foreground">Not yet</span>
                          )}
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(v.created_at)}</TD>
                        <TD>
                          <StatusBadge status={v.status} />
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Async>
        </Section>

        <Section
          title="Corrections"
          description="Where a credited amount was later restated, and by how much."
          bodyClassName="p-0 pt-0"
        >
          <Async
            query={vouchers}
            isEmpty={(d) => d.corrections.length === 0}
            emptyTitle="No corrections"
            emptyDescription="Nothing credited to you has been restated."
            skeleton={
              <div className="p-5">
                <Skeleton className="h-24 w-full" />
              </div>
            }
          >
            {(data) => (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Package</TH>
                      <TH className="text-right">Was</TH>
                      <TH className="text-right">Now</TH>
                      <TH className="text-right">Difference</TH>
                      <TH>Reason</TH>
                      <TH>Corrected</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {data.corrections.map((c) => {
                      const diff = Number(c.difference ?? 0);
                      return (
                        <TR key={c.id}>
                          <TD className="max-w-64 truncate font-medium">{c.package_type}</TD>
                          <TD className="tabular text-right text-muted-foreground">
                            {Number(c.previous_amount).toLocaleString('en-IE')}
                          </TD>
                          <TD className="tabular text-right">
                            {Number(c.corrected_amount).toLocaleString('en-IE')}
                          </TD>
                          <TD className="text-right">
                            <Badge tone={diff >= 0 ? 'success' : 'danger'}>
                              {diff >= 0 ? '+' : ''}
                              {diff.toLocaleString('en-IE')}
                            </Badge>
                          </TD>
                          <TD className="max-w-64 truncate text-muted-foreground">
                            {c.correction_reason ?? c.correction_type}
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(c.corrected_at)}</TD>
                        </TR>
                      );
                    })}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Async>
        </Section>
      </div>
    </>
  );
}

/* ------------------------------------------------------------------------ */

function RedeemForm() {
  const { user } = useAuth();
  const redeem = useRedeemVoucher();

  const [tokenType, setTokenType] = useState(VOUCHER_TOKEN_TYPES[0]);
  const [packageType, setPackageType] = useState(VOUCHER_PACKAGES[VOUCHER_TOKEN_TYPES[0]][0].value);
  const [paymentType, setPaymentType] = useState(VOUCHER_PAYMENT_TYPES[0].value);
  const [fullName, setFullName] = useState('');
  const [strDomeUsername, setStrDomeUsername] = useState('');
  const [strDomeEmail, setStrDomeEmail] = useState('');
  const [depositAddress, setDepositAddress] = useState('');
  const [paymentHash, setPaymentHash] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [amount, setAmount] = useState('');

  const packages = VOUCHER_PACKAGES[tokenType] ?? [];
  const selected = useMemo(
    () => packages.find((p) => p.value === packageType) ?? packages[0],
    [packages, packageType]
  );
  const requires = VOUCHER_PAYMENT_TYPES.find((p) => p.value === paymentType)?.requires;

  // CCOS claims settle inside the platform, so no external deposit address
  // applies to them.
  const needsDepositAddress = tokenType !== 'ccos';

  const hashValid = /^(0x)?[a-fA-F0-9]{64}$/.test(paymentHash.trim());
  const amountValid = /^\d+(\.\d{1,2})?$/.test(amount.trim());

  const canSubmit =
    fullName.trim().length > 1 &&
    strDomeUsername.trim().length > 0 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(strDomeEmail) &&
    (!needsDepositAddress || depositAddress.trim().length > 0) &&
    (requires === 'hash' ? hashValid : true) &&
    (requires === 'confirmation' ? confirmation.trim().length > 0 && amountValid : true) &&
    !redeem.isPending;

  function changeTokenType(next: string) {
    setTokenType(next);
    setPackageType(VOUCHER_PACKAGES[next]?.[0]?.value ?? '');
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit || !selected) return;

    try {
      await redeem.mutateAsync({
        tokenType,
        // The stored label is matched by the correction jobs, so it is written
        // exactly as it appears in the package table — never reformatted, and
        // never with a thousands separator, which is what broke the match in v2.
        packageType: selected.value,
        paymentType,
        fullName: fullName.trim(),
        emailAddress: user?.email ?? strDomeEmail.trim(),
        strDomeUsername: strDomeUsername.trim().toLowerCase(),
        strDomeEmail: strDomeEmail.trim(),
        depositAddress: needsDepositAddress ? depositAddress.trim() : null,
        paymentHash: requires === 'hash' ? paymentHash.trim() : null,
        confirmationNumber: requires === 'confirmation' ? confirmation.trim() : null,
        amount: requires === 'confirmation' ? amount.trim() : null,
      });
      toast.success('Voucher claim submitted for review.');
      setPaymentHash('');
      setConfirmation('');
      setAmount('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the claim');
    }
  }

  return (
    <Section
      title="Claim a voucher"
      description="Pick the package you bought. The token amount is set by the server on review."
    >
      <form className="grid gap-4 md:grid-cols-2" onSubmit={submit}>
        <div className="space-y-1.5">
          <Label htmlFor="v-token">Token</Label>
          <select
            id="v-token"
            value={tokenType}
            onChange={(e) => changeTokenType(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm uppercase"
          >
            {VOUCHER_TOKEN_TYPES.map((t) => (
              <option key={t} value={t}>
                {t.toUpperCase()}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="v-package">Package</Label>
          <select
            id="v-package"
            value={packageType}
            onChange={(e) => setPackageType(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {packages.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </select>
          {selected && (
            <p className="text-xs text-muted-foreground">
              {money(selected.usd, 'USD')} · indicative{' '}
              {selected.tokens.toLocaleString('en-IE', { maximumFractionDigits: 2 })}{' '}
              {tokenType.toUpperCase()}
            </p>
          )}
        </div>

        <Field label="Full name" htmlFor="v-name">
          <Input
            id="v-name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            autoComplete="name"
            required
          />
        </Field>

        <Field label="STR.Dome username" htmlFor="v-username">
          <Input
            id="v-username"
            value={strDomeUsername}
            onChange={(e) => setStrDomeUsername(e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <Field label="STR.Dome email" htmlFor="v-email">
          <Input
            id="v-email"
            type="email"
            value={strDomeEmail}
            onChange={(e) => setStrDomeEmail(e.target.value)}
            autoComplete="email"
            required
          />
        </Field>

        {needsDepositAddress && (
          <Field
            label="Receiving wallet"
            htmlFor="v-wallet"
            hint="Where the tokens should be delivered."
          >
            <Input
              id="v-wallet"
              value={depositAddress}
              onChange={(e) => setDepositAddress(e.target.value)}
              spellCheck={false}
              required
            />
          </Field>
        )}

        <div className="space-y-1.5">
          <Label htmlFor="v-payment">Paid by</Label>
          <select
            id="v-payment"
            value={paymentType}
            onChange={(e) => setPaymentType(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {VOUCHER_PAYMENT_TYPES.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </select>
        </div>

        {requires === 'hash' && (
          <Field
            label="Transaction hash"
            htmlFor="v-hash"
            error={
              paymentHash.trim().length > 0 && !hashValid
                ? 'A transaction hash is 64 hexadecimal characters.'
                : undefined
            }
            hint="Checked against the chain during review, not here."
          >
            <Input
              id="v-hash"
              value={paymentHash}
              onChange={(e) => setPaymentHash(e.target.value)}
              spellCheck={false}
              required
            />
          </Field>
        )}

        {requires === 'confirmation' && (
          <>
            <Field label="Confirmation number" htmlFor="v-conf">
              <Input
                id="v-conf"
                value={confirmation}
                onChange={(e) => setConfirmation(e.target.value)}
                spellCheck={false}
                required
              />
            </Field>
            <Field
              label="Amount paid"
              htmlFor="v-amount"
              error={
                amount.trim().length > 0 && !amountValid ? 'Enter an amount like 2500.00.' : undefined
              }
            >
              <Input
                id="v-amount"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                required
              />
            </Field>
          </>
        )}

        <div className="flex items-end md:col-span-2">
          <Button type="submit" disabled={!canSubmit}>
            <Ticket aria-hidden="true" />
            {redeem.isPending ? 'Submitting…' : 'Submit claim'}
          </Button>
        </div>
      </form>
    </Section>
  );
}
