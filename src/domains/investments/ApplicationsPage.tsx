import { useMemo, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { FileText } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate, maskIban } from '@/lib/format';
import { useAuth } from '@/features/auth/AuthProvider';
import {
  IPO_LISTING_CURRENCIES,
  IPO_LISTING_PRICE_PER_SHARE,
  IPO_LISTING_SHARE_TYPES,
} from './constants';
import { Async, LockedAction, Section } from './shared';
import { useCreateIpoListingRequest, useMyCommitments, useMyIpoListingRequests } from './hooks';

/**
 * Subscriptions the member has made, and their standing.
 *
 * The six source tables are read as one list — a member's position is a
 * position regardless of which round produced it.
 */
export default function ApplicationsPage() {
  const commitments = useMyCommitments();

  return (
    <>
      <PageHeader
        title="My applications"
        description="Every subscription you have made, and where each one stands."
      />

      <div className="space-y-6">
        <Section
          title="Subscriptions"
          description="Across the seed rounds, the STR sales, the digital share issue and the SAFE."
          bodyClassName="p-0 pt-0"
        >
          <Async
            query={commitments}
            isEmpty={(rows) => rows.length === 0}
            emptyTitle="No subscriptions yet"
            emptyDescription="Nothing has been submitted against your account."
            skeleton={
              <div className="p-5">
                <Skeleton className="h-40 w-full" />
              </div>
            }
          >
            {(rows) => (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Offering</TH>
                      <TH className="text-right">Amount</TH>
                      <TH className="text-right">Quantity</TH>
                      <TH>Submitted</TH>
                      <TH>Payment</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {rows.map((row) => (
                      <TR key={`${row.kind}-${row.id}`}>
                        <TD className="font-medium">{row.offering}</TD>
                        <TD className="tabular text-right">{money(row.amountUsd, 'USD')}</TD>
                        <TD className="tabular text-right text-muted-foreground">
                          {row.quantity === null
                            ? '—'
                            : `${row.quantity.toLocaleString('en-IE')} ${row.quantityUnit ?? ''}`}
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(row.createdAt)}</TD>
                        <TD>
                          {row.paymentStatus ? (
                            <StatusBadge status={row.paymentStatus} />
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
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
          </Async>
        </Section>

        <Section
          title="Apply to a round"
          description="Applications carry an audit trail that the browser is not allowed to write."
        >
          {/* TODO(server): needs a submit-seed-str-application edge function.
              Both seed tables require a non-null ip_address, and the audit row
              in seed_str_audit_log / private_seed_str_audit_log is only worth
              keeping if the server writes it. v2 sent the literal "0.0.0.0",
              wrote its own audit entry, and set status directly to "approved"
              on insert — the applicant approved their own application. */}
          <LockedAction
            label="Start an application"
            reason="Seed applications are opened server-side so the recorded address, the audit entry and the approval decision cannot come from the applicant."
          />
        </Section>

        <IpoListingSection />
      </div>
    </>
  );
}

/* ------------------------------------------------------------------------ */

const EMPTY_FORM = {
  fullName: '',
  email: '',
  phone: '',
  address: '',
  shareType: IPO_LISTING_SHARE_TYPES[0].value,
  numberOfShares: '',
  receivingCurrency: IPO_LISTING_CURRENCIES[0],
  iban: '',
  bankName: '',
  bankSwift: '',
  signature: '',
};

/**
 * Requesting that existing holdings be listed for the IPO.
 *
 * This one is a genuine client write, because it moves nothing: it records an
 * intent for an admin to price and settle. The price is still sent — the
 * column is NOT NULL — but it is the server's number at approval that counts.
 */
function IpoListingSection() {
  const { user } = useAuth();
  const requests = useMyIpoListingRequests();
  const create = useCreateIpoListingRequest();
  const [form, setForm] = useState({ ...EMPTY_FORM, email: user?.email ?? '' });

  const shares = Number(form.numberOfShares);
  const total = useMemo(
    () => (Number.isFinite(shares) && shares > 0 ? shares * IPO_LISTING_PRICE_PER_SHARE : 0),
    [shares]
  );

  const signatureMatches =
    form.signature.trim().length > 0 &&
    form.signature.trim().toLowerCase() === form.fullName.trim().toLowerCase();

  const canSubmit =
    form.fullName.trim().length > 1 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email) &&
    Number.isInteger(shares) &&
    shares > 0 &&
    form.iban.trim().length >= 8 &&
    form.bankName.trim().length > 1 &&
    form.bankSwift.trim().length >= 8 &&
    signatureMatches &&
    !create.isPending;

  function set<K extends keyof typeof EMPTY_FORM>(key: K, value: string) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await create.mutateAsync({
        fullName: form.fullName.trim(),
        email: form.email.trim(),
        phone: form.phone.trim() || null,
        address: form.address.trim() || null,
        shareType: form.shareType,
        numberOfShares: shares,
        pricePerShare: IPO_LISTING_PRICE_PER_SHARE,
        receivingCurrency: form.receivingCurrency,
        iban: form.iban.replace(/\s+/g, '').toUpperCase(),
        bankName: form.bankName.trim(),
        bankSwift: form.bankSwift.trim().toUpperCase(),
      });
      toast.success('Listing request submitted for review.');
      setForm({ ...EMPTY_FORM, email: user?.email ?? '' });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the request');
    }
  }

  return (
    <Section
      title="IPO listing requests"
      description={`Offer existing holdings into the IPO at ${money(IPO_LISTING_PRICE_PER_SHARE, 'USD')} per share.`}
    >
      <form className="grid gap-4 md:grid-cols-2" onSubmit={submit}>
        <Field label="Full name" htmlFor="ipo-name">
          <Input
            id="ipo-name"
            value={form.fullName}
            onChange={(e) => set('fullName', e.target.value)}
            autoComplete="name"
            required
          />
        </Field>

        <Field label="Email" htmlFor="ipo-email">
          <Input
            id="ipo-email"
            type="email"
            value={form.email}
            onChange={(e) => set('email', e.target.value)}
            autoComplete="email"
            required
          />
        </Field>

        <Field label="Phone" htmlFor="ipo-phone" hint="Optional.">
          <Input
            id="ipo-phone"
            value={form.phone}
            onChange={(e) => set('phone', e.target.value)}
            autoComplete="tel"
          />
        </Field>

        <Field label="Address" htmlFor="ipo-address" hint="Optional.">
          <Input
            id="ipo-address"
            value={form.address}
            onChange={(e) => set('address', e.target.value)}
            autoComplete="street-address"
          />
        </Field>

        <div className="space-y-1.5">
          <Label htmlFor="ipo-type">Share type</Label>
          <select
            id="ipo-type"
            value={form.shareType}
            onChange={(e) => set('shareType', e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {IPO_LISTING_SHARE_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
        </div>

        <Field
          label="Number of shares"
          htmlFor="ipo-shares"
          hint={total > 0 ? `Gross value ${money(total, 'USD')}` : 'Whole shares only.'}
        >
          <Input
            id="ipo-shares"
            type="number"
            min="1"
            step="1"
            value={form.numberOfShares}
            onChange={(e) => set('numberOfShares', e.target.value)}
            required
          />
        </Field>

        <div className="space-y-1.5">
          <Label htmlFor="ipo-currency">Receiving currency</Label>
          <select
            id="ipo-currency"
            value={form.receivingCurrency}
            onChange={(e) => set('receivingCurrency', e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {IPO_LISTING_CURRENCIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>

        <Field label="IBAN" htmlFor="ipo-iban">
          <Input
            id="ipo-iban"
            value={form.iban}
            onChange={(e) => set('iban', e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <Field label="Bank name" htmlFor="ipo-bank">
          <Input
            id="ipo-bank"
            value={form.bankName}
            onChange={(e) => set('bankName', e.target.value)}
            required
          />
        </Field>

        <Field label="SWIFT / BIC" htmlFor="ipo-swift">
          <Input
            id="ipo-swift"
            value={form.bankSwift}
            onChange={(e) => set('bankSwift', e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <Field
          label="Signature"
          htmlFor="ipo-signature"
          error={
            form.signature.trim().length > 0 && !signatureMatches
              ? 'Type your full name exactly as entered above.'
              : undefined
          }
          hint="Typing your name here confirms the request."
        >
          <Input
            id="ipo-signature"
            value={form.signature}
            onChange={(e) => set('signature', e.target.value)}
            required
          />
        </Field>

        <div className="flex items-end md:col-span-2">
          <Button type="submit" disabled={!canSubmit}>
            <FileText aria-hidden="true" />
            {create.isPending ? 'Submitting…' : 'Submit listing request'}
          </Button>
        </div>
      </form>

      <div className="mt-6 border-t border-border pt-4">
        <Async
          query={requests}
          isEmpty={(rows) => rows.length === 0}
          emptyTitle="No listing requests"
          emptyDescription="Requests you submit will appear here with their review status."
          skeleton={<Skeleton className="h-24 w-full" />}
        >
          {(rows) => (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Type</TH>
                    <TH className="text-right">Shares</TH>
                    <TH className="text-right">Value</TH>
                    <TH>Payout to</TH>
                    <TH>Submitted</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((row) => (
                    <TR key={row.id}>
                      <TD className="font-medium">
                        {IPO_LISTING_SHARE_TYPES.find((t) => t.value === row.share_type)?.label ??
                          row.share_type}
                      </TD>
                      <TD className="tabular text-right">
                        {Number(row.number_of_shares).toLocaleString('en-IE')}
                      </TD>
                      <TD className="tabular text-right">
                        {money(row.total_usd_value, 'USD')}
                      </TD>
                      <TD className="tabular text-muted-foreground">{maskIban(row.iban)}</TD>
                      <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                      <TD>
                        <div className="space-y-1">
                          <StatusBadge status={row.status} />
                          {row.admin_message && (
                            <p className="max-w-60 text-xs text-muted-foreground">
                              {row.admin_message}
                            </p>
                          )}
                        </div>
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Async>
      </div>
    </Section>
  );
}
