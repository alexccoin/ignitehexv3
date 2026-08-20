import { useEffect, useMemo, useState, type FormEvent } from 'react';
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
import { money, shortDate } from '@/lib/format';
import {
  VOUCHER_PACKAGES,
  VOUCHER_PAYMENT_TYPES,
  VOUCHER_TOKEN_LABELS,
  VOUCHER_TOKEN_TYPES,
  STR_VOUCHER_TERMS,
  type VoucherTokenType,
} from './constants';
import { useBonusProfile, useMyVouchers, useSubmitVoucherClaim } from './hooks';
import { Async, Section, amountLabel } from './shared';

/**
 * Voucher claims: submit one, and follow what it was credited.
 *
 * The claim form writes a pending row and nothing else. The member picks a
 * package rather than typing an amount, because an amount typed here would be a
 * number the browser chose, and the server decides what a voucher is worth
 * against its own table when it reviews the claim.
 */
export default function Vouchers() {
  const vouchers = useMyVouchers();

  const rows = vouchers.data?.redemptions ?? [];
  const credited = rows.filter((v) => v.tokens_credited === true).length;
  const pending = rows.filter((v) => v.status === 'pending').length;

  return (
    <>
      <PageHeader
        title="Vouchers"
        description="Claim a voucher and follow it through review, crediting and any later restatement."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Claims"
          value={String(rows.length)}
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
          value={String(credited)}
          sub="Released to your account"
          loading={vouchers.isLoading}
          tone="success"
        />
      </div>

      <div className="space-y-6">
        <ClaimForm />
        <StrLadder />

        <Section title="Your claims" bodyClassName="p-0 pt-0">
          <Async
            query={vouchers}
            isEmpty={(d) => d.redemptions.length === 0}
            emptyTitle="No voucher claims"
            emptyDescription="Claims you submit are listed here with their review status."
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
                        {/*
                          Rendered verbatim. The string in this column is what
                          the correction jobs match on, so it is never
                          prettified — not here, and above all not on the way in.
                        */}
                        <TD className="max-w-72 truncate font-medium" title={v.package_type}>
                          {v.package_type}
                        </TD>
                        <TD className="uppercase text-muted-foreground">{v.token_type}</TD>
                        <TD className="capitalize text-muted-foreground">{v.payment_type}</TD>
                        <TD className="tabular text-right">
                          {v.tokens_credited === true ? (
                            amountLabel(v.token_type.toLowerCase(), Number(v.credited_amount ?? 0))
                          ) : (
                            <span className="text-muted-foreground">Not yet valued</span>
                          )}
                        </TD>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {shortDate(v.created_at)}
                        </TD>
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
                      const symbol = c.token_type.toLowerCase();
                      const diff = Number(c.difference ?? 0);
                      return (
                        <TR key={c.id}>
                          <TD className="max-w-72 truncate font-medium" title={c.package_type}>
                            {c.package_type}
                          </TD>
                          <TD className="tabular text-right text-muted-foreground">
                            {amountLabel(symbol, Number(c.previous_amount))}
                          </TD>
                          <TD className="tabular text-right">
                            {amountLabel(symbol, Number(c.corrected_amount))}
                          </TD>
                          <TD className="text-right">
                            <Badge tone={diff >= 0 ? 'success' : 'danger'}>
                              {diff >= 0 ? '+' : '−'}
                              {amountLabel(symbol, Math.abs(diff))}
                            </Badge>
                          </TD>
                          <TD className="max-w-64 truncate text-muted-foreground">
                            {c.correction_reason ?? c.correction_type}
                          </TD>
                          <TD className="whitespace-nowrap text-muted-foreground">
                            {shortDate(c.corrected_at)}
                          </TD>
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

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
/** A transaction hash is 64 hex characters, optionally 0x-prefixed. */
const TX_HASH = /^(0x)?[a-fA-F0-9]{64}$/;
const DECIMAL = /^\d+(\.\d{1,2})?$/;

function ClaimForm() {
  const profile = useBonusProfile();
  const submit = useSubmitVoucherClaim();

  const [tokenType, setTokenType] = useState<VoucherTokenType>('str');
  const [packageType, setPackageType] = useState(VOUCHER_PACKAGES.str[0].value);
  const [paymentType, setPaymentType] = useState(VOUCHER_PAYMENT_TYPES[0].value);
  const [fullName, setFullName] = useState('');
  const [strDomeUsername, setStrDomeUsername] = useState('');
  const [strDomeEmail, setStrDomeEmail] = useState('');
  const [paymentHash, setPaymentHash] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [amount, setAmount] = useState('');

  // Prefill from the member's own profile once it arrives, rather than asking
  // them to retype their name and domain into a fourth form. v2 stored whatever
  // was typed, which is why the voucher tables hold several spellings of the
  // same person.
  const prefill = profile.data;
  useEffect(() => {
    if (!prefill) return;
    setFullName((v) => v || prefill.fullName);
    setStrDomeUsername((v) => v || prefill.strDomainUsername);
    setStrDomeEmail((v) => v || prefill.emailAddress);
  }, [prefill]);

  const packages = VOUCHER_PACKAGES[tokenType];
  const selected = useMemo(
    () => packages.find((p) => p.value === packageType) ?? packages[0],
    [packages, packageType]
  );
  const requires = VOUCHER_PAYMENT_TYPES.find((p) => p.value === paymentType)?.requires ?? 'none';

  // CCOS is settled inside the platform, so no external deposit address applies.
  const needsWallet = tokenType !== 'ccos';
  const wallet = prefill?.strWalletAddress ?? '';

  const hashValid = TX_HASH.test(paymentHash.trim());
  const amountValid = DECIMAL.test(amount.trim());

  const canSubmit =
    fullName.trim().length > 1 &&
    strDomeUsername.trim().length > 0 &&
    EMAIL.test(strDomeEmail.trim()) &&
    (!needsWallet || wallet.length > 0) &&
    (requires !== 'hash' || hashValid) &&
    (requires !== 'confirmation' || (confirmation.trim().length > 0 && amountValid)) &&
    !submit.isPending;

  function changeToken(next: string) {
    const t = VOUCHER_TOKEN_TYPES.find((v) => v === next) ?? 'str';
    setTokenType(t);
    setPackageType(VOUCHER_PACKAGES[t][0].value);
  }

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await submit.mutateAsync({
        tokenType,
        // Written through unchanged. Not trimmed, not re-cased, not formatted:
        // the correction jobs match this string byte for byte, and v2's
        // toLocaleString'd variants are exactly why they stopped matching.
        packageType: selected.value,
        paymentType,
        fullName: fullName.trim(),
        emailAddress: prefill?.emailAddress ?? strDomeEmail.trim(),
        strDomeUsername: strDomeUsername.trim().toLowerCase(),
        strDomeEmail: strDomeEmail.trim(),
        depositAddress: needsWallet ? wallet : null,
        paymentHash: requires === 'hash' ? paymentHash.trim() : null,
        confirmationNumber: requires === 'confirmation' ? confirmation.trim() : null,
        amount: requires === 'confirmation' ? amount.trim() : null,
      });
      toast.success('Voucher claim submitted for review.');
      setPaymentHash('');
      setConfirmation('');
      setAmount('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the claim.');
    }
  }

  return (
    <Section
      title="Claim a voucher"
      description="Pick the package you bought. The token amount is decided by the server when the claim is reviewed."
    >
      <form className="grid gap-4 md:grid-cols-2" onSubmit={onSubmit}>
        <div className="space-y-1.5">
          <Label htmlFor="bv-token">Token</Label>
          <select
            id="bv-token"
            value={tokenType}
            onChange={(e) => changeToken(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {VOUCHER_TOKEN_TYPES.map((t) => (
              <option key={t} value={t}>
                {VOUCHER_TOKEN_LABELS[t]}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="bv-package">Package</Label>
          {/*
            The option text is the stored value itself. Showing a prettified
            label beside a differently-formatted stored value is how v2 ended up
            with a package column nobody could match against.
          */}
          <select
            id="bv-package"
            value={packageType}
            onChange={(e) => setPackageType(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {packages.map((p) => (
              <option key={p.value} value={p.value}>
                {p.value}
              </option>
            ))}
          </select>
          <p className="text-xs text-muted-foreground">
            {money(selected.usd, 'USD')} · indicative only until the server values the claim.
          </p>
        </div>

        <Field label="Full name" htmlFor="bv-name">
          <Input
            id="bv-name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            autoComplete="name"
            required
          />
        </Field>

        <Field label="STR.Dome username" htmlFor="bv-username">
          <Input
            id="bv-username"
            value={strDomeUsername}
            onChange={(e) => setStrDomeUsername(e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <Field
          label="STR.Dome email"
          htmlFor="bv-email"
          error={
            strDomeEmail.trim().length > 0 && !EMAIL.test(strDomeEmail.trim())
              ? 'Enter a valid email address.'
              : undefined
          }
        >
          <Input
            id="bv-email"
            type="email"
            value={strDomeEmail}
            onChange={(e) => setStrDomeEmail(e.target.value)}
            autoComplete="email"
            required
          />
        </Field>

        {needsWallet && (
          <Field
            label="Receiving wallet"
            htmlFor="bv-wallet"
            hint={
              wallet
                ? 'Taken from your account. Tokens are delivered here.'
                : 'No wallet address on your account yet — set one up before claiming.'
            }
            error={profile.isLoading || wallet ? undefined : 'A receiving wallet is required.'}
          >
            {/*
              Read-only on purpose: the delivery address is the one on the
              member's own account, not one typed into a claim form.
            */}
            <Input
              id="bv-wallet"
              value={wallet}
              readOnly
              aria-readonly="true"
              spellCheck={false}
              className="font-mono text-xs"
            />
          </Field>
        )}

        <div className="space-y-1.5">
          <Label htmlFor="bv-payment">Paid by</Label>
          <select
            id="bv-payment"
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
            htmlFor="bv-hash"
            error={
              paymentHash.trim().length > 0 && !hashValid
                ? 'A transaction hash is 64 hexadecimal characters.'
                : undefined
            }
            hint="Verified against the chain during review, not here."
          >
            <Input
              id="bv-hash"
              value={paymentHash}
              onChange={(e) => setPaymentHash(e.target.value)}
              spellCheck={false}
              required
            />
          </Field>
        )}

        {requires === 'confirmation' && (
          <>
            <Field label="Confirmation number" htmlFor="bv-conf">
              <Input
                id="bv-conf"
                value={confirmation}
                onChange={(e) => setConfirmation(e.target.value)}
                spellCheck={false}
                required
              />
            </Field>
            <Field
              label="Amount paid"
              htmlFor="bv-amount"
              error={
                amount.trim().length > 0 && !amountValid ? 'Enter an amount like 2500.00.' : undefined
              }
            >
              <Input
                id="bv-amount"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                required
              />
            </Field>
          </>
        )}

        {requires === 'none' && (
          <p className="self-end text-xs text-muted-foreground md:col-span-1">
            Bank transfers are matched against the treasury statement during review. Keep your
            receipt — an operator may ask for it.
          </p>
        )}

        <div className="flex items-end md:col-span-2">
          <Button type="submit" disabled={!canSubmit}>
            <Ticket aria-hidden="true" />
            {submit.isPending ? 'Submitting…' : 'Submit claim'}
          </Button>
        </div>
      </form>
    </Section>
  );
}

/* ------------------------------------------------------------------------ */

/** The STR pre-listing ladder and its terms. */
function StrLadder() {
  return (
    <Section
      title="STR pre-listing voucher programme"
      description="Fixed allocations at 0.0015 USD per STR, vesting 30 days after the CEX listing."
      bodyClassName="space-y-5 p-5"
    >
      <ul className="space-y-2">
        {STR_VOUCHER_TERMS.map((term) => (
          <li key={term} className="flex gap-2 text-sm text-muted-foreground">
            <span aria-hidden="true" className="mt-2 size-1.5 shrink-0 rounded-full bg-primary" />
            {term}
          </li>
        ))}
      </ul>

      <TableWrap>
        <Table>
          <THead>
            <TR>
              <TH>Voucher</TH>
              <TH className="text-right">Price</TH>
              <TH className="text-right">STR allocation</TH>
            </TR>
          </THead>
          <TBody>
            {VOUCHER_PACKAGES.str.map((p) => (
              <TR key={p.value}>
                {/* The stored label, shown as stored. */}
                <TD className="font-medium">{p.value}</TD>
                <TD className="tabular text-right">{money(p.usd, 'USD')}</TD>
                <TD className="tabular text-right text-muted-foreground">
                  {amountLabel('str', p.tokens)}
                </TD>
              </TR>
            ))}
          </TBody>
        </Table>
      </TableWrap>
    </Section>
  );
}
