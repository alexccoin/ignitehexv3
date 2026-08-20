import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Rocket } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import { AIRDROP_EVENT_TYPES } from './constants';
import { useBonusProfile, useMyAirdrop, useMyVouchers, useRegisterAirdrop } from './hooks';
import { Async, Section, amountLabel } from './shared';

/**
 * Airdrop registration and its history.
 *
 * A registration is a request, not an entitlement, and this screen says so: the
 * requested amount is labelled as requested until the server records a credited
 * amount against the row. v2 showed the requested figure in an "amount" column
 * with no qualification, so members read a pending row as tokens they already
 * had.
 */
export default function Airdrop() {
  const registrations = useMyAirdrop();

  const rows = registrations.data ?? [];
  const pending = rows.filter((r) => r.status === 'pending').length;
  const credited = rows
    .filter((r) => r.tokens_credited === true)
    .reduce((sum, r) => sum + Number(r.credited_amount ?? 0), 0);

  return (
    <>
      <PageHeader
        title="Airdrop"
        description="Register for an allocation and follow the review."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Registrations"
          value={String(rows.length)}
          loading={registrations.isLoading}
          icon={<Rocket className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Under review"
          value={String(pending)}
          loading={registrations.isLoading}
          tone={pending > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Credited"
          value={amountLabel('arss', credited)}
          sub="Released by the server"
          loading={registrations.isLoading}
          tone="success"
        />
      </div>

      <div className="space-y-6">
        <RegisterForm />

        <Section title="Your registrations" bodyClassName="p-0 pt-0">
          <Async
            query={registrations}
            isEmpty={(d) => d.length === 0}
            emptyTitle="Not registered yet"
            emptyDescription="Register above and the request will appear here with its review status."
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
                      <TH>Registered</TH>
                      <TH>Event</TH>
                      <TH className="text-right">Requested</TH>
                      <TH className="text-right">Credited</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {data.map((r) => (
                      <TR key={r.id}>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {shortDate(r.created_at)}
                        </TD>
                        <TD className="uppercase">{r.event_type ?? '—'}</TD>
                        <TD className="tabular text-right text-muted-foreground">
                          {amountLabel('arss', Number(r.requested_amount))}
                        </TD>
                        <TD className="tabular text-right">
                          {r.tokens_credited === true ? (
                            amountLabel('arss', Number(r.credited_amount ?? 0))
                          ) : (
                            <span className="text-muted-foreground">Not yet</span>
                          )}
                        </TD>
                        <TD>
                          <StatusBadge status={r.status} />
                        </TD>
                      </TR>
                    ))}
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

function RegisterForm() {
  const profile = useBonusProfile();
  const vouchers = useMyVouchers();
  const register = useRegisterAirdrop();

  const [eventType, setEventType] = useState(AIRDROP_EVENT_TYPES[0].value);
  const [requested, setRequested] = useState('1000');
  const [voucherId, setVoucherId] = useState('');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');

  const prefill = profile.data;
  useEffect(() => {
    if (!prefill) return;
    setFullName((v) => v || prefill.fullName);
    setEmail((v) => v || prefill.emailAddress);
  }, [prefill]);

  // A registration can be attached to a voucher that has been approved but not
  // yet credited, which is how the SourceLess event pairs the two.
  const linkable = useMemo(
    () =>
      (vouchers.data?.redemptions ?? []).filter(
        (v) => v.status === 'approved' && v.tokens_credited !== true
      ),
    [vouchers.data]
  );

  const wallet = prefill?.strWalletAddress ?? '';
  const amount = Number(requested);
  const amountValid = Number.isFinite(amount) && amount > 0;

  const canSubmit =
    fullName.trim().length > 1 &&
    email.trim().length > 3 &&
    wallet.length > 0 &&
    amountValid &&
    !register.isPending;

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await register.mutateAsync({
        fullName: fullName.trim(),
        emailAddress: email.trim(),
        walletAddress: wallet,
        requestedAmount: amount,
        eventType,
        voucherId: voucherId || null,
      });
      toast.success('Airdrop registration submitted for review.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not register.');
    }
  }

  if (profile.isLoading) {
    return (
      <Section title="Register">
        <Skeleton className="h-40 w-full" />
      </Section>
    );
  }

  return (
    <Section
      title="Register"
      description="Tokens are released by an operator after review. Registering asks for an allocation; it does not grant one."
    >
      <form className="grid gap-4 md:grid-cols-2" onSubmit={onSubmit}>
        <div className="space-y-1.5">
          <Label htmlFor="ad-event">Event</Label>
          <select
            id="ad-event"
            value={eventType}
            onChange={(e) => setEventType(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          >
            {AIRDROP_EVENT_TYPES.map((e) => (
              <option key={e.value} value={e.value}>
                {e.label}
              </option>
            ))}
          </select>
        </div>

        <Field
          label="Requested ARSS"
          htmlFor="ad-amount"
          error={requested.length > 0 && !amountValid ? 'Enter an amount above zero.' : undefined}
          hint="What you are asking for. The operator decides what is credited."
        >
          <Input
            id="ad-amount"
            inputMode="decimal"
            value={requested}
            onChange={(e) => setRequested(e.target.value)}
            required
          />
        </Field>

        <Field label="Full name" htmlFor="ad-name">
          <Input
            id="ad-name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            autoComplete="name"
            required
          />
        </Field>

        <Field label="Email" htmlFor="ad-email">
          <Input
            id="ad-email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            required
          />
        </Field>

        <Field
          label="Receiving wallet"
          htmlFor="ad-wallet"
          hint={
            wallet
              ? 'Taken from your account.'
              : 'No wallet address on your account yet — set one up before registering.'
          }
          error={wallet ? undefined : 'A receiving wallet is required.'}
        >
          <Input
            id="ad-wallet"
            value={wallet}
            readOnly
            aria-readonly="true"
            spellCheck={false}
            className="font-mono text-xs"
          />
        </Field>

        <div className="space-y-1.5">
          <Label htmlFor="ad-voucher">Linked voucher</Label>
          <select
            id="ad-voucher"
            value={voucherId}
            onChange={(e) => setVoucherId(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
            disabled={linkable.length === 0}
          >
            <option value="">None</option>
            {/* Package labels are shown exactly as stored. */}
            {linkable.map((v) => (
              <option key={v.id} value={v.id}>
                {v.package_type}
              </option>
            ))}
          </select>
          <p className="text-xs text-muted-foreground">
            {linkable.length === 0
              ? 'No approved, uncredited voucher to attach.'
              : 'Optional. Attaches this registration to an approved voucher.'}
          </p>
        </div>

        <div className="md:col-span-2">
          <Button type="submit" disabled={!canSubmit}>
            <Rocket aria-hidden="true" />
            {register.isPending ? 'Submitting…' : 'Register'}
          </Button>
        </div>
      </form>
    </Section>
  );
}
