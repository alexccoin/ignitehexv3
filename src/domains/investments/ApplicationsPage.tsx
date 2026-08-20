import { useMemo, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { FileText } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate, maskIban } from '@/lib/format';
import { useAuth } from '@/features/auth/AuthProvider';
import {
  IPO_LISTING_CURRENCIES,
  IPO_LISTING_PRICE_PER_SHARE,
  IPO_LISTING_SHARE_TYPES,
  SEED_MIN_USD,
  SEED_SHARE_PRICE,
  SEED_TIERS,
  STR_REFERENCE_PRICE,
} from './constants';
import { cn } from '@/lib/utils';
import { Async, Section } from './shared';
import type { SeedRound } from './hooks';
import {
  useCreateIpoListingRequest,
  useCreateSeedApplication,
  useMyCommitments,
  useMyIpoListingRequests,
} from './hooks';

/** One place for the address check both forms on this page use. */
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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

        <ApplySection commitments={commitments} />

        <IpoListingSection />
      </div>
    </>
  );
}

/* ------------------------------------------------------------------------ */

const SEED_ROUNDS: { value: SeedRound; label: string; note: string }[] = [
  {
    value: 'seed_str',
    label: 'STR seed round',
    note: 'Open round. Shares plus an STR entitlement, locked for 12 months.',
  },
  {
    value: 'private_seed_str',
    label: 'Private STR seed round',
    note: 'By invitation. Carries a subscription agreement, so an address and a signature are required.',
  },
];

const EMPTY_APPLICATION = {
  round: 'seed_str' as SeedRound,
  fullName: '',
  email: '',
  tier: SEED_TIERS[0].value,
  amountUsd: '',
  signatureFirstName: '',
  signatureLastName: '',
  phone: '',
  streetAddress: '',
  city: '',
  stateProvince: '',
  postalCode: '',
  country: '',
};

const CONSENTS = [
  {
    id: 'terms',
    title: 'Subscription terms',
    body: 'I have read the terms of the round, including the 12-month lock on any STR entitlement.',
  },
  {
    id: 'nda',
    title: 'Non-disclosure',
    body: 'I will not disclose the offering materials I have been given access to.',
  },
  {
    id: 'risk',
    title: 'Risk disclosure',
    body: 'I understand this is an early-stage, illiquid investment and that I may lose the entire amount.',
  },
  {
    id: 'gdpr',
    title: 'Data processing',
    body: 'I consent to the details on this form being processed for the purpose of reviewing this application.',
  },
];

/**
 * Applying to a seed round.
 *
 * This writes a pending row and nothing else. What makes it safe is not
 * anything in this component - it is that the applicant holds no UPDATE right
 * on `seed_str_applications` at all, and that on the private table a trigger
 * refuses any change to `status`. The form does not try to enforce that a
 * second time; a form cannot.
 *
 * The amount is entered in USD because USD is what a member commits. The STR
 * and share figures shown beside it are the same conversion `useMyCommitments`
 * applies when reading the row back, so the member sees the numbers before
 * submitting rather than discovering them afterwards.
 */
function ApplySection({ commitments }: { commitments: ReturnType<typeof useMyCommitments> }) {
  const { user } = useAuth();
  const create = useCreateSeedApplication();
  const [form, setForm] = useState({ ...EMPTY_APPLICATION, email: user?.email ?? '' });
  const [accepted, setAccepted] = useState<Record<string, boolean>>({});

  const isPrivate = form.round === 'private_seed_str';
  const tier = SEED_TIERS.find((t) => t.value === form.tier) ?? SEED_TIERS[0];

  // The professional tier declares no floor of its own, so the round minimum
  // applies to it instead of zero.
  const minUsd = Math.max(tier.minUsd, SEED_MIN_USD);
  const amountUsd = Number(form.amountUsd);
  const amountValid =
    Number.isFinite(amountUsd) &&
    amountUsd >= minUsd &&
    (tier.maxUsd === null || amountUsd <= tier.maxUsd);

  const amountError =
    form.amountUsd.trim() === '' || amountValid
      ? undefined
      : tier.maxUsd === null
        ? `Minimum ${money(minUsd, 'USD')} for this tier.`
        : `${tier.label} runs from ${money(minUsd, 'USD')} to ${money(tier.maxUsd, 'USD')}.`;

  const allConsented = CONSENTS.every((c) => accepted[c.id]);

  const canSubmit =
    form.fullName.trim().length > 1 &&
    EMAIL.test(form.email) &&
    amountValid &&
    allConsented &&
    (!isPrivate ||
      (form.signatureFirstName.trim().length > 0 &&
        form.signatureLastName.trim().length > 0 &&
        form.streetAddress.trim().length > 2 &&
        form.city.trim().length > 1 &&
        form.country.trim().length > 1)) &&
    !create.isPending;

  function set<K extends keyof typeof EMPTY_APPLICATION>(key: K, value: string) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await create.mutateAsync({
        round: form.round,
        fullName: form.fullName.trim(),
        email: form.email.trim(),
        tier: form.tier,
        amountUsd,
        termsAccepted: true,
        ndaAccepted: true,
        gdprAccepted: true,
        riskAccepted: true,
        signatureFirstName: isPrivate ? form.signatureFirstName.trim() : null,
        signatureLastName: isPrivate ? form.signatureLastName.trim() : null,
        phone: isPrivate ? form.phone.trim() || null : null,
        streetAddress: isPrivate ? form.streetAddress.trim() : null,
        city: isPrivate ? form.city.trim() : null,
        stateProvince: isPrivate ? form.stateProvince.trim() || null : null,
        postalCode: isPrivate ? form.postalCode.trim() || null : null,
        country: isPrivate ? form.country.trim() : null,
      });
      toast.success('Application submitted. It is now awaiting review.');
      setForm({ ...EMPTY_APPLICATION, email: user?.email ?? '', round: form.round });
      setAccepted({});
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the application');
    }
  }

  // Only the two seed kinds, because those are the rows this form produces.
  const openApplications = (commitments.data ?? []).filter(
    (c) =>
      (c.kind === 'seed_str' || c.kind === 'private_seed_str') &&
      c.status !== 'approved' &&
      c.status !== 'rejected'
  );

  return (
    <Section
      title="Apply to a round"
      description={`Shares are ${money(SEED_SHARE_PRICE, 'USD')} each, STR is priced at $${STR_REFERENCE_PRICE}. An application is a request; the reviewer decides it.`}
    >
      <form className="space-y-5" onSubmit={submit}>
        <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Round">
          {SEED_ROUNDS.map((round) => (
            <button
              key={round.value}
              type="button"
              role="radio"
              aria-checked={form.round === round.value}
              onClick={() => set('round', round.value)}
              className={cn(
                'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
                form.round === round.value
                  ? 'bg-primary/10 text-primary ring-primary/20'
                  : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
              )}
            >
              {round.label}
            </button>
          ))}
        </div>
        <p className="text-xs text-muted-foreground">
          {SEED_ROUNDS.find((r) => r.value === form.round)?.note}
        </p>

        <div className="grid gap-4 md:grid-cols-2">
          <Field label="Full name" htmlFor="seed-name">
            <Input
              id="seed-name"
              value={form.fullName}
              onChange={(e) => set('fullName', e.target.value)}
              autoComplete="name"
              required
            />
          </Field>

          <Field label="Email" htmlFor="seed-email">
            <Input
              id="seed-email"
              type="email"
              value={form.email}
              onChange={(e) => set('email', e.target.value)}
              autoComplete="email"
              required
            />
          </Field>

          <div className="space-y-1.5">
            <Label htmlFor="seed-tier">Tier</Label>
            <select
              id="seed-tier"
              value={form.tier}
              onChange={(e) => set('tier', e.target.value)}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
            >
              {SEED_TIERS.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label} - {t.description}
                </option>
              ))}
            </select>
          </div>

          <Field
            label="Amount (USD)"
            htmlFor="seed-amount"
            error={amountError}
            hint={
              amountValid
                ? `${(amountUsd / SEED_SHARE_PRICE).toLocaleString('en-IE', { maximumFractionDigits: 2 })} shares, ${(amountUsd / STR_REFERENCE_PRICE).toLocaleString('en-IE', { maximumFractionDigits: 0 })} STR`
                : `Minimum ${money(minUsd, 'USD')}.`
            }
          >
            <Input
              id="seed-amount"
              type="number"
              min={minUsd}
              step="1"
              value={form.amountUsd}
              onChange={(e) => set('amountUsd', e.target.value)}
              aria-invalid={!!amountError}
              required
            />
          </Field>

          {isPrivate && (
            <>
              <Field label="Signature - first name" htmlFor="seed-sig-first">
                <Input
                  id="seed-sig-first"
                  value={form.signatureFirstName}
                  onChange={(e) => set('signatureFirstName', e.target.value)}
                  required
                />
              </Field>

              <Field label="Signature - last name" htmlFor="seed-sig-last">
                <Input
                  id="seed-sig-last"
                  value={form.signatureLastName}
                  onChange={(e) => set('signatureLastName', e.target.value)}
                  required
                />
              </Field>

              <Field label="Phone" htmlFor="seed-phone" hint="Optional.">
                <Input
                  id="seed-phone"
                  value={form.phone}
                  onChange={(e) => set('phone', e.target.value)}
                  autoComplete="tel"
                />
              </Field>

              <Field label="Street address" htmlFor="seed-street">
                <Input
                  id="seed-street"
                  value={form.streetAddress}
                  onChange={(e) => set('streetAddress', e.target.value)}
                  autoComplete="street-address"
                  required
                />
              </Field>

              <Field label="City" htmlFor="seed-city">
                <Input
                  id="seed-city"
                  value={form.city}
                  onChange={(e) => set('city', e.target.value)}
                  autoComplete="address-level2"
                  required
                />
              </Field>

              <Field label="State / province" htmlFor="seed-state" hint="Optional.">
                <Input
                  id="seed-state"
                  value={form.stateProvince}
                  onChange={(e) => set('stateProvince', e.target.value)}
                  autoComplete="address-level1"
                />
              </Field>

              <Field label="Postal code" htmlFor="seed-postal" hint="Optional.">
                <Input
                  id="seed-postal"
                  value={form.postalCode}
                  onChange={(e) => set('postalCode', e.target.value)}
                  autoComplete="postal-code"
                />
              </Field>

              <Field label="Country" htmlFor="seed-country">
                <Input
                  id="seed-country"
                  value={form.country}
                  onChange={(e) => set('country', e.target.value)}
                  autoComplete="country-name"
                  required
                />
              </Field>
            </>
          )}
        </div>

        <div className="space-y-3">
          {CONSENTS.map((consent) => (
            <label
              key={consent.id}
              htmlFor={`seed-consent-${consent.id}`}
              className="flex cursor-pointer gap-3 rounded-lg border border-border p-3 transition-colors hover:bg-elevated"
            >
              <input
                id={`seed-consent-${consent.id}`}
                type="checkbox"
                className="mt-0.5 size-4 shrink-0 rounded border-border accent-primary"
                checked={!!accepted[consent.id]}
                onChange={(e) =>
                  setAccepted((prev) => ({ ...prev, [consent.id]: e.target.checked }))
                }
              />
              <span>
                <span className="block text-sm font-medium">{consent.title}</span>
                <span className="mt-1 block text-xs text-muted-foreground">{consent.body}</span>
              </span>
            </label>
          ))}
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <Button type="submit" disabled={!canSubmit}>
            <FileText aria-hidden="true" />
            {create.isPending ? 'Submitting...' : 'Submit application'}
          </Button>
          <p className="text-xs text-muted-foreground">
            A submitted application appears in Subscriptions above, and in the list below, at
            pending until a reviewer decides it.
          </p>
        </div>
      </form>

      <div className="mt-6 border-t border-border pt-4">
        <h4 className="mb-3 text-sm font-medium">Applications awaiting a decision</h4>
        {commitments.isLoading ? (
          <Skeleton className="h-16 w-full" />
        ) : commitments.isError ? (
          <ErrorState
            title="Could not load your applications"
            error={commitments.error}
            onRetry={() => void commitments.refetch()}
          />
        ) : openApplications.length === 0 ? (
          <EmptyState
            title="Nothing awaiting review"
            description="An application you submit is listed here until it is approved or rejected."
          />
        ) : (
          <ul className="space-y-2">
            {openApplications.map((row) => (
              <li
                key={`${row.kind}-${row.id}`}
                className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-3"
              >
                <div>
                  <p className="text-sm font-medium">{row.offering}</p>
                  <p className="tabular text-xs text-muted-foreground">
                    {money(row.amountUsd, 'USD')} · submitted {shortDate(row.createdAt)}
                  </p>
                </div>
                <StatusBadge status={row.status} />
              </li>
            ))}
          </ul>
        )}
      </div>
    </Section>
  );
}

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
    EMAIL.test(form.email) &&
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
