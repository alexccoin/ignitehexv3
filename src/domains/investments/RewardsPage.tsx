import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Copy, Gift, Users } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { ErrorState } from '@/components/ui/states';
import { Stat } from '@/components/ui/stat';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate, token } from '@/lib/format';
import { useAuth } from '@/features/auth/AuthProvider';
import { AIRDROP_EVENT_TYPES, AIRDROP_VOUCHER_TYPES } from './constants';
import { Async, Detail, LockedAction, Section } from './shared';
import {
  useAffiliateReferrals,
  useCreateAffiliate,
  useMyAffiliate,
  useMyAirdrop,
  useRegisterAirdrop,
} from './hooks';

/**
 * The two ways a member earns without subscribing: the airdrop, and referrals.
 *
 * Both register an intent. Neither credits anything — `tokens_credited` and
 * `commission_amount` are written by the server after review, and are not
 * columns this page can reach.
 */
export default function RewardsPage() {
  const airdrop = useMyAirdrop();
  const affiliate = useMyAffiliate();

  const registrations = airdrop.data ?? [];
  const creditedTokens = registrations.reduce((sum, r) => sum + Number(r.credited_amount ?? 0), 0);

  return (
    <>
      <PageHeader
        title="Rewards"
        description="Airdrop registrations and referral earnings."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Airdrop registrations"
          value={String(registrations.length)}
          loading={airdrop.isLoading}
          icon={<Gift className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Airdrop credited"
          value={creditedTokens.toLocaleString('en-IE')}
          sub="Tokens released"
          loading={airdrop.isLoading}
          tone="success"
        />
        <Stat
          label="Referrals"
          value={String(affiliate.data?.total_referrals ?? 0)}
          sub={`${affiliate.data?.total_conversions ?? 0} converted`}
          loading={affiliate.isLoading}
          icon={<Users className="size-4" aria-hidden="true" />}
        />
      </div>

      <div className="space-y-6">
        <AirdropSection />
        <AffiliateSection />
      </div>
    </>
  );
}

/* --------------------------------------------------------------- airdrop */

/** Default allocation requested when no voucher is attached. */
const DEFAULT_REQUEST = 1000;

function AirdropSection() {
  const { user } = useAuth();
  const airdrop = useMyAirdrop();
  const register = useRegisterAirdrop();

  const [fullName, setFullName] = useState('');
  const [walletAddress, setWalletAddress] = useState('');
  const [eventType, setEventType] = useState(AIRDROP_EVENT_TYPES[0].value);
  const [voucherType, setVoucherType] = useState('');

  const hasOpenRegistration = (airdrop.data ?? []).some((r) => r.status === 'pending');

  const canSubmit =
    fullName.trim().length > 1 &&
    walletAddress.trim().length > 8 &&
    !hasOpenRegistration &&
    !register.isPending;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await register.mutateAsync({
        fullName: fullName.trim(),
        emailAddress: user?.email ?? '',
        walletAddress: walletAddress.trim(),
        // The allocation is a request, not an entitlement. The reviewer sets
        // the credited amount; this number only says what was asked for.
        requestedAmount: DEFAULT_REQUEST,
        eventType,
        voucherType: eventType === 'sourceless' && voucherType ? voucherType : null,
        voucherId: null,
      });
      toast.success('Airdrop registration submitted.');
      setWalletAddress('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not register');
    }
  }

  return (
    <Section
      title="Airdrop"
      description="One open registration at a time. Tokens are credited after review."
    >
      <form className="grid gap-4 md:grid-cols-2" onSubmit={submit}>
        <Field label="Full name" htmlFor="a-name">
          <Input
            id="a-name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            autoComplete="name"
            disabled={hasOpenRegistration}
            required
          />
        </Field>

        <Field label="Wallet address" htmlFor="a-wallet" hint="Where the tokens will be sent.">
          <Input
            id="a-wallet"
            value={walletAddress}
            onChange={(e) => setWalletAddress(e.target.value)}
            spellCheck={false}
            disabled={hasOpenRegistration}
            required
          />
        </Field>

        <div className="space-y-1.5">
          <Label htmlFor="a-event">Event</Label>
          <select
            id="a-event"
            value={eventType}
            onChange={(e) => setEventType(e.target.value)}
            disabled={hasOpenRegistration}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm disabled:opacity-50"
          >
            {AIRDROP_EVENT_TYPES.map((e) => (
              <option key={e.value} value={e.value}>
                {e.label}
              </option>
            ))}
          </select>
        </div>

        {eventType === 'sourceless' && (
          <div className="space-y-1.5">
            <Label htmlFor="a-voucher">Linked voucher</Label>
            <select
              id="a-voucher"
              value={voucherType}
              onChange={(e) => setVoucherType(e.target.value)}
              disabled={hasOpenRegistration}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm uppercase disabled:opacity-50"
            >
              <option value="">None</option>
              {AIRDROP_VOUCHER_TYPES.map((v) => (
                <option key={v} value={v}>
                  {v.toUpperCase()}
                </option>
              ))}
            </select>
          </div>
        )}

        <div className="flex items-end md:col-span-2">
          <Button type="submit" disabled={!canSubmit}>
            <Gift aria-hidden="true" />
            {register.isPending ? 'Submitting…' : 'Register'}
          </Button>
          {hasOpenRegistration && (
            <p className="ml-3 text-xs text-muted-foreground">
              You already have a registration awaiting review.
            </p>
          )}
        </div>
      </form>

      <div className="mt-6 border-t border-border pt-4">
        <Async
          query={airdrop}
          isEmpty={(rows) => rows.length === 0}
          emptyTitle="No registrations"
          emptyDescription="Registrations you submit will be listed here."
          skeleton={<Skeleton className="h-24 w-full" />}
        >
          {(rows) => (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Event</TH>
                    <TH>Wallet</TH>
                    <TH className="text-right">Requested</TH>
                    <TH className="text-right">Credited</TH>
                    <TH>Registered</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((r) => (
                    <TR key={r.id}>
                      <TD className="font-medium uppercase">
                        {r.event_type ?? '—'}
                        {r.voucher_type && (
                          <Badge tone="neutral" className="ml-2">
                            {r.voucher_type}
                          </Badge>
                        )}
                      </TD>
                      <TD className="tabular max-w-40 truncate text-xs text-muted-foreground">
                        {r.wallet_address}
                      </TD>
                      <TD className="tabular text-right">
                        {Number(r.requested_amount).toLocaleString('en-IE')}
                      </TD>
                      <TD className="tabular text-right">
                        {r.tokens_credited ? (
                          Number(r.credited_amount ?? 0).toLocaleString('en-IE')
                        ) : (
                          <span className="text-muted-foreground">Not yet</span>
                        )}
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(r.created_at)}</TD>
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
      </div>
    </Section>
  );
}

/* ------------------------------------------------------------- referrals */

function AffiliateSection() {
  const affiliate = useMyAffiliate();

  if (affiliate.isLoading) {
    return (
      <Section title="Referrals">
        <Skeleton className="h-32 w-full" />
      </Section>
    );
  }

  // A failed lookup must not fall through to the sign-up form: offering to
  // enrol someone who is already an affiliate produces a unique violation and
  // reads as "your account was lost".
  if (affiliate.isError) {
    return (
      <Section title="Referrals" bodyClassName="p-0 pt-0">
        <ErrorState
          title="Could not load your affiliate account"
          error={affiliate.error}
          onRetry={() => void affiliate.refetch()}
        />
      </Section>
    );
  }

  if (affiliate.data) {
    return <AffiliateDashboard affiliate={affiliate.data} />;
  }

  return <AffiliateSignup />;
}

type Affiliate = NonNullable<ReturnType<typeof useMyAffiliate>['data']>;

function AffiliateDashboard({ affiliate }: { affiliate: Affiliate }) {
  const referrals = useAffiliateReferrals(affiliate.id);
  const link = `${window.location.origin}/auth?ref=${affiliate.affiliate_code}`;

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      toast.success('Referral link copied.');
    } catch {
      toast.error('Could not copy the link.');
    }
  }

  return (
    <Section
      title="Referrals"
      description="Your referral link and the introductions made through it."
      actions={
        <Button variant="secondary" size="icon" onClick={() => void copy()} aria-label="Copy referral link">
          <Copy aria-hidden="true" />
        </Button>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Detail label="Code" value={affiliate.affiliate_code} />
        <Detail label="Status" value={<StatusBadge status={affiliate.status ?? 'active'} />} />
        <Detail
          label="Referred volume"
          value={money(affiliate.total_investment_referred ?? 0, 'USD')}
        />
        <Detail label="Joined" value={shortDate(affiliate.created_at)} />
      </div>

      <p className="tabular mt-4 break-all rounded-md bg-elevated px-3 py-2 text-xs text-muted-foreground">
        {link}
      </p>

      {/* TODO(server): commission accrual belongs in a settle-affiliate-commission
          function. v2 incremented seed_str_affiliates.total_referrals straight
          from the browser on every visit to a referral link, from an anonymous
          session, so the counter could be inflated by reloading the page. */}
      <LockedAction
        className="mt-4"
        label="Withdraw commission"
        reason="Commission is accrued and paid out server-side; the browser cannot move it."
      />

      <div className="mt-6 border-t border-border pt-4">
        <Async
          query={referrals}
          isEmpty={(rows) => rows.length === 0}
          emptyTitle="No referrals yet"
          emptyDescription="Introductions made through your link will appear here."
          skeleton={<Skeleton className="h-24 w-full" />}
        >
          {(rows) => (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Referred</TH>
                    <TH className="text-right">Investment</TH>
                    <TH className="text-right">Commission</TH>
                    <TH>Converted</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((r) => (
                    <TR key={r.id}>
                      <TD className="text-muted-foreground">{shortDate(r.created_at)}</TD>
                      <TD className="tabular text-right">
                        {r.investment_amount ? money(r.investment_amount, 'USD') : '—'}
                      </TD>
                      <TD className="tabular text-right">
                        {r.commission_amount ? token(r.commission_amount, 'wstr') : '—'}
                      </TD>
                      <TD className="text-muted-foreground">
                        {r.converted_at ? shortDate(r.converted_at) : '—'}
                      </TD>
                      <TD>
                        <StatusBadge status={r.status ?? 'clicked'} />
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

const EVM_ADDRESS = /^0x[a-fA-F0-9]{40}$/;
const PAYOUT_NETWORKS = ['ethereum', 'polygon'];

function AffiliateSignup() {
  const { user } = useAuth();
  const create = useCreateAffiliate();

  const [fullName, setFullName] = useState('');
  const [strDomain, setStrDomain] = useState('');
  const [usdt, setUsdt] = useState('');
  const [usdtNetwork, setUsdtNetwork] = useState(PAYOUT_NETWORKS[0]);
  const [usdc, setUsdc] = useState('');
  const [usdcNetwork, setUsdcNetwork] = useState(PAYOUT_NETWORKS[0]);

  const usdtValid = EVM_ADDRESS.test(usdt.trim());
  const usdcValid = EVM_ADDRESS.test(usdc.trim());

  const canSubmit =
    fullName.trim().length > 1 &&
    strDomain.trim().length > 1 &&
    usdtValid &&
    usdcValid &&
    !create.isPending;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await create.mutateAsync({
        fullName: fullName.trim(),
        email: user?.email ?? '',
        strDomain: strDomain.trim(),
        usdtAddress: usdt.trim(),
        usdtNetwork,
        usdcAddress: usdc.trim(),
        usdcNetwork,
      });
      toast.success('You are now registered as an affiliate.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not register');
    }
  }

  return (
    <Section
      title="Become an affiliate"
      description="Your referral code is your STR domain, so it cannot collide with anyone else's."
    >
      <form className="grid gap-4 md:grid-cols-2" onSubmit={submit}>
        <Field label="Full name" htmlFor="af-name">
          <Input
            id="af-name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            autoComplete="name"
            required
          />
        </Field>

        <Field label="STR domain" htmlFor="af-domain" hint="The str. prefix is dropped.">
          <Input
            id="af-domain"
            value={strDomain}
            onChange={(e) => setStrDomain(e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <Field
          label="USDT payout address"
          htmlFor="af-usdt"
          error={usdt.trim().length > 0 && !usdtValid ? 'Enter a valid EVM address.' : undefined}
        >
          <Input
            id="af-usdt"
            value={usdt}
            onChange={(e) => setUsdt(e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <div className="space-y-1.5">
          <Label htmlFor="af-usdt-net">USDT network</Label>
          <select
            id="af-usdt-net"
            value={usdtNetwork}
            onChange={(e) => setUsdtNetwork(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm capitalize"
          >
            {PAYOUT_NETWORKS.map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </div>

        <Field
          label="USDC payout address"
          htmlFor="af-usdc"
          error={usdc.trim().length > 0 && !usdcValid ? 'Enter a valid EVM address.' : undefined}
        >
          <Input
            id="af-usdc"
            value={usdc}
            onChange={(e) => setUsdc(e.target.value)}
            spellCheck={false}
            required
          />
        </Field>

        <div className="space-y-1.5">
          <Label htmlFor="af-usdc-net">USDC network</Label>
          <select
            id="af-usdc-net"
            value={usdcNetwork}
            onChange={(e) => setUsdcNetwork(e.target.value)}
            className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm capitalize"
          >
            {PAYOUT_NETWORKS.map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </div>

        <div className="flex items-end md:col-span-2">
          <Button type="submit" disabled={!canSubmit}>
            <Users aria-hidden="true" />
            {create.isPending ? 'Registering…' : 'Register as affiliate'}
          </Button>
        </div>
      </form>
    </Section>
  );
}
