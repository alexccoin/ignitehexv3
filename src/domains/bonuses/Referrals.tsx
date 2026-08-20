import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Coins, Handshake, TrendingUp, Users } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { EmptyState } from '@/components/ui/states';
import { money, shortDate } from '@/lib/format';
import {
  useAffiliateReferrals,
  useBonusProfile,
  useCreateAffiliate,
  useMyAffiliate,
  useMyReferrals,
  type AffiliateRow,
} from './hooks';
import {
  EVM_ADDRESS,
  PAYOUT_NETWORKS,
  REFERRAL_RATE_COPY,
  REFERRAL_STEPS,
} from './constants';
import { Async, CopyField, Detail, LockedAction, Section, amountLabel } from './shared';
import { PayoutAddressForm } from './PayoutForm';

/**
 * The referral programme: your link, your referrals, and the affiliate scheme
 * that sits on top of it.
 *
 * The counts on this screen are counted by the database. v2 kept a
 * `total_referrals` column on the affiliate row and incremented it with a plain
 * UPDATE from the public referral landing page — a page an anonymous visitor
 * could load, so the counter went up once per refresh by anyone at all, and the
 * affiliate dashboard reported it as the number of people they had brought in.
 * Nothing here writes a counter, and nothing here reads one.
 */
export default function Referrals() {
  const profile = useBonusProfile();
  const referrals = useMyReferrals();
  const affiliate = useMyAffiliate();

  const claimed = (referrals.data?.rows ?? []).filter((r) => r.reward_claimed === true);
  const unclaimed = (referrals.data?.rows ?? []).filter((r) => r.reward_claimed !== true);

  // Both figures are sums of amounts the server itself wrote to the rows.
  const earned = claimed.reduce((sum, r) => sum + Number(r.reward_amount ?? 0), 0);
  const awaiting = unclaimed.reduce((sum, r) => sum + Number(r.reward_amount ?? 0), 0);

  const code = profile.data?.referralCode ?? affiliate.data?.affiliate_code ?? null;
  const link = code ? `${window.location.origin}/auth?ref=${code}` : null;

  return (
    <>
      <PageHeader title="Referrals" description={`Earn ${REFERRAL_RATE_COPY}.`} />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Referrals"
          value={String(referrals.data?.total ?? 0)}
          sub="Counted by the server"
          loading={referrals.isLoading}
          icon={<Users className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Converted"
          value={String(claimed.length)}
          sub="Commission released"
          loading={referrals.isLoading}
          tone="success"
          icon={<TrendingUp className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Commission earned"
          value={amountLabel('wstr', earned)}
          loading={referrals.isLoading}
          tone="success"
          icon={<Coins className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Awaiting release"
          value={amountLabel('wstr', awaiting)}
          sub={`${unclaimed.length} referral${unclaimed.length === 1 ? '' : 's'}`}
          loading={referrals.isLoading}
          tone={awaiting > 0 ? 'warning' : 'default'}
        />
      </div>

      <div className="space-y-6">
        <Section
          title="Your referral link"
          description="Anyone who signs up through this link is attributed to you."
        >
          {profile.isLoading ? (
            <Skeleton className="h-9 w-full" />
          ) : link ? (
            <div className="space-y-4">
              <CopyField value={link} label="Referral link" />
              <div className="grid gap-4 sm:grid-cols-3">
                {REFERRAL_STEPS.map((step, i) => (
                  <div key={step.title} className="space-y-1">
                    <p className="flex items-center gap-2 text-sm font-medium">
                      <span
                        aria-hidden="true"
                        className="flex size-5 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary"
                      >
                        {i + 1}
                      </span>
                      {step.title}
                    </p>
                    <p className="text-xs text-muted-foreground">{step.body}</p>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <EmptyState
              title="No referral code yet"
              description="Your account has not been issued a referral code. It is generated server-side when your profile is completed."
            />
          )}
        </Section>

        <Section
          title="Your referrals"
          description="What the server has recorded against your code."
          bodyClassName="p-0 pt-0"
        >
          <Async
            query={referrals}
            isEmpty={(d) => d.rows.length === 0}
            emptyTitle="No referrals yet"
            emptyDescription="Share your link. Anyone who signs up through it appears here."
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
                      <TH>Referred</TH>
                      <TH>Status</TH>
                      <TH className="text-right">Your commission</TH>
                      <TH>Released</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {/*
                      No name column. v2 pulled every referred member's
                      full_name and email_address into the referrer's browser to
                      decorate this table — other people's contact details,
                      handed to a third party, to render a string.
                    */}
                    {data.rows.map((r) => (
                      <TR key={r.id}>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {shortDate(r.created_at)}
                        </TD>
                        <TD>
                          <StatusBadge status={r.status} />
                        </TD>
                        <TD className="tabular text-right">
                          {r.reward_amount === null ? (
                            <span className="text-muted-foreground">Not yet valued</span>
                          ) : (
                            amountLabel('wstr', Number(r.reward_amount))
                          )}
                        </TD>
                        <TD>
                          {r.reward_claimed === true ? (
                            <Badge tone="success">{shortDate(r.claimed_at)}</Badge>
                          ) : (
                            <Badge tone="warning">Pending</Badge>
                          )}
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Async>
        </Section>

        {/*
          TODO(server): a `claim_referral_rewards(p_referral_ids uuid[])` RPC
          that, in one statement, marks the rows claimed and credits the wSTR.
          Until it exists this stays disabled — claiming from the browser would
          mean reading a balance, adding to it and writing it back, which is the
          pattern that lost credits in v2 at ~25 sites.
        */}
        <Section
          title="Releasing commission"
          description="Commission is released by the server once a referral settles."
        >
          <LockedAction
            label="Claim released commission"
            reason="Not available from the browser. Crediting a balance has to happen in one server-side statement, and no endpoint exists for referral claims yet — commission is released automatically when a referral converts."
          />
        </Section>

        <Section
          title="Affiliate programme"
          description="Enrol your str.domain to earn commission on seed round investments you introduce."
        >
          <Async
            query={affiliate}
            skeleton={<Skeleton className="h-32 w-full" />}
            isEmpty={() => false}
          >
            {(row) => (row ? <AffiliatePanel affiliate={row} /> : <EnrolPanel />)}
          </Async>
        </Section>
      </div>
    </>
  );
}

/* ------------------------------------------------------------------------ */

function AffiliatePanel({ affiliate }: { affiliate: AffiliateRow }) {
  const referrals = useAffiliateReferrals(affiliate.id);
  const link = `${window.location.origin}/ref/${affiliate.affiliate_code}`;

  return (
    <div className="space-y-6">
      <div className="grid gap-5 sm:grid-cols-4">
        <Detail label="Code" value={<span className="font-mono">{affiliate.affiliate_code}</span>} />
        <Detail label="Status" value={<StatusBadge status={affiliate.status} />} />
        {/*
          Counted with `count: 'exact'` over the referral rows, not read from
          seed_str_affiliates.total_referrals — that column was writable by any
          anonymous visitor to the referral landing page in v2.
        */}
        <Detail
          label="Referrals"
          value={referrals.isLoading ? <Skeleton as="span" className="h-4 w-10" /> : referrals.data?.total ?? 0}
        />
        <Detail
          label="Converted"
          value={
            referrals.isLoading ? <Skeleton as="span" className="h-4 w-10" /> : referrals.data?.converted ?? 0
          }
        />
      </div>

      <div className="space-y-2">
        <Label>Affiliate link</Label>
        <CopyField value={link} label="Affiliate link" />
      </div>

      <PayoutAddressForm affiliate={affiliate} />

      <div>
        <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Introductions
        </p>
        <Async
          query={referrals}
          isEmpty={(d) => d.rows.length === 0}
          emptyTitle="No introductions yet"
          emptyDescription="Investors who apply through your affiliate link appear here."
          skeleton={<Skeleton className="h-24 w-full" />}
        >
          {(data) => (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Introduced</TH>
                    <TH>Status</TH>
                    <TH className="text-right">Investment</TH>
                    <TH className="text-right">Commission</TH>
                    <TH>Converted</TH>
                  </TR>
                </THead>
                <TBody>
                  {data.rows.map((r) => (
                    <TR key={r.id}>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(r.created_at)}
                      </TD>
                      <TD>
                        <StatusBadge status={r.status} />
                      </TD>
                      <TD className="tabular text-right">
                        {r.investment_amount === null ? '—' : money(Number(r.investment_amount), 'USD')}
                      </TD>
                      <TD className="tabular text-right">
                        {r.commission_amount === null ? '—' : money(Number(r.commission_amount), 'USD')}
                      </TD>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {r.converted_at ? shortDate(r.converted_at) : 'Not yet'}
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Async>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------------ */

function EnrolPanel() {
  const profile = useBonusProfile();
  const enrol = useCreateAffiliate();

  const [usdtAddress, setUsdtAddress] = useState('');
  const [usdtNetwork, setUsdtNetwork] = useState(PAYOUT_NETWORKS[0]);
  const [usdcAddress, setUsdcAddress] = useState('');
  const [usdcNetwork, setUsdcNetwork] = useState(PAYOUT_NETWORKS[0]);

  const domain = profile.data?.mainDomain ?? null;
  const code = domain?.replace(/^str\./i, '').toLowerCase() ?? '';

  const usdtValid = EVM_ADDRESS.test(usdtAddress.trim());
  const usdcValid = EVM_ADDRESS.test(usdcAddress.trim());
  const canSubmit = !!domain && usdtValid && usdcValid && !enrol.isPending;

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit || !profile.data) return;

    try {
      await enrol.mutateAsync({
        fullName: profile.data.fullName,
        email: profile.data.emailAddress,
        strDomain: domain!,
        usdtAddress: usdtAddress.trim(),
        usdtNetwork,
        usdcAddress: usdcAddress.trim(),
        usdcNetwork,
      });
      toast.success('You are enrolled as an affiliate.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not enrol.');
    }
  }

  if (profile.isLoading) return <Skeleton className="h-40 w-full" />;

  if (!domain) {
    return (
      <EmptyState
        icon={<Handshake className="size-5" aria-hidden="true" />}
        title="A minted str.domain is required"
        description="Your affiliate code is your own domain, so it cannot collide with anyone else's. Mint a main domain first and this section will open up."
      />
    );
  }

  return (
    <form className="grid gap-4 md:grid-cols-2" onSubmit={onSubmit}>
      <div className="md:col-span-2">
        <p className="text-sm text-muted-foreground">
          Your affiliate code will be{' '}
          <span className="font-mono font-medium text-foreground">{code}</span>, taken from your main
          domain. Commission is paid to the addresses below.
        </p>
      </div>

      <Field
        label="USDT address"
        htmlFor="af-usdt"
        error={usdtAddress.length > 0 && !usdtValid ? 'Enter a valid EVM address (0x…).' : undefined}
      >
        <Input
          id="af-usdt"
          value={usdtAddress}
          onChange={(e) => setUsdtAddress(e.target.value)}
          spellCheck={false}
          className="font-mono text-xs"
          required
        />
      </Field>

      <div className="space-y-1.5">
        <Label htmlFor="af-usdt-net">USDT network</Label>
        <select
          id="af-usdt-net"
          value={usdtNetwork}
          onChange={(e) => setUsdtNetwork(e.target.value)}
          className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
        >
          {PAYOUT_NETWORKS.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </div>

      <Field
        label="USDC address"
        htmlFor="af-usdc"
        error={usdcAddress.length > 0 && !usdcValid ? 'Enter a valid EVM address (0x…).' : undefined}
      >
        <Input
          id="af-usdc"
          value={usdcAddress}
          onChange={(e) => setUsdcAddress(e.target.value)}
          spellCheck={false}
          className="font-mono text-xs"
          required
        />
      </Field>

      <div className="space-y-1.5">
        <Label htmlFor="af-usdc-net">USDC network</Label>
        <select
          id="af-usdc-net"
          value={usdcNetwork}
          onChange={(e) => setUsdcNetwork(e.target.value)}
          className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
        >
          {PAYOUT_NETWORKS.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </div>

      <div className="md:col-span-2">
        <Button type="submit" disabled={!canSubmit}>
          <Handshake aria-hidden="true" />
          {enrol.isPending ? 'Enrolling…' : 'Enrol as an affiliate'}
        </Button>
      </div>
    </form>
  );
}
