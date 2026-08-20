import { Link } from 'react-router-dom';
import { ArrowUpRight, Coins, Landmark, PieChart, ShieldCheck } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Stat } from '@/components/ui/stat';
import { ErrorState } from '@/components/ui/states';
import { money, shortDate, token } from '@/lib/format';
import { IPO_PHASES, OFFERINGS, SEED_STAGES, SEED_TIERS } from './constants';
import { LockedAction, Section } from './shared';
import { useMyCommitments, useShareHoldings } from './hooks';

/**
 * What is on offer, and where the member already stands.
 *
 * v2 scattered these across a dozen unlinked marketing pages, each with its
 * own copy of the terms; several quoted prices that no longer agreed. One
 * catalogue, one price per instrument.
 */
export default function OfferingsPage() {
  const commitments = useMyCommitments();
  const holdings = useShareHoldings();

  const rows = commitments.data ?? [];
  const committedUsd = rows.reduce((sum, r) => sum + r.amountUsd, 0);
  const settled = rows.filter(
    (r) => r.paymentStatus === 'credited' || r.status === 'approved'
  ).length;

  const shares = holdings.data?.shares;
  const vestingTotal = (holdings.data?.vesting ?? [])
    .filter((v) => v.status !== 'released')
    .reduce((sum, v) => sum + Number(v.amount ?? 0), 0);

  return (
    <>
      <PageHeader
        title="Investments"
        description="Every round, sale and node programme in one place, with the terms that actually apply."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Committed"
          value={money(committedUsd, 'USD')}
          sub={`${rows.length} subscription${rows.length === 1 ? '' : 's'}`}
          icon={<Landmark className="size-4" aria-hidden="true" />}
          loading={commitments.isLoading}
          tone="primary"
        />
        <Stat
          label="Settled"
          value={String(settled)}
          sub="Approved or credited"
          icon={<ShieldCheck className="size-4" aria-hidden="true" />}
          loading={commitments.isLoading}
          tone="success"
        />
        <Stat
          label="Share balance"
          value={Number(shares?.balance ?? 0).toLocaleString('en-IE')}
          sub={
            shares?.locked_balance
              ? `${Number(shares.locked_balance).toLocaleString('en-IE')} locked`
              : 'Unlocked'
          }
          icon={<PieChart className="size-4" aria-hidden="true" />}
          loading={holdings.isLoading}
        />
        <Stat
          label="Vesting"
          value={token(vestingTotal, 'str')}
          sub="Not yet released"
          icon={<Coins className="size-4" aria-hidden="true" />}
          loading={holdings.isLoading}
        />
      </div>

      {/* The figures above read zero when a query fails, which is why the
          failure is stated rather than left to look like an empty portfolio. */}
      {(commitments.isError || holdings.isError) && (
        <Card className="mb-6">
          <CardContent className="p-0">
            <ErrorState
              title="Could not load your position"
              error={commitments.error ?? holdings.error}
              onRetry={() => {
                if (commitments.isError) void commitments.refetch();
                if (holdings.isError) void holdings.refetch();
              }}
            />
          </CardContent>
        </Card>
      )}

      <div className="mb-6 grid gap-4 lg:grid-cols-2">
        {OFFERINGS.map((offering) => (
          <Card key={offering.id}>
            <CardContent className="space-y-4">
              <div className="flex items-start justify-between gap-3">
                <div className="space-y-1">
                  <h3 className="font-semibold tracking-tight">{offering.name}</h3>
                  <p className="text-sm text-muted-foreground">{offering.instrument}</p>
                </div>
                {offering.restricted && <Badge tone="warning">By invitation</Badge>}
              </div>

              <dl className="grid grid-cols-2 gap-3 border-t border-border pt-3 text-sm">
                <div>
                  <dt className="text-xs uppercase tracking-wide text-muted-foreground">Price</dt>
                  <dd className="tabular mt-0.5 font-medium">{offering.price}</dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-muted-foreground">Terms</dt>
                  <dd className="mt-0.5">{offering.terms}</dd>
                </div>
              </dl>

              {/* TODO(server): subscribing to any of the blocked offerings needs a
                  create-investment-order edge function that (a) checks the
                  member's entitlement for the restricted rounds, (b) prices the
                  order from the server's own rate, and (c) issues the treasury
                  address with the order. Until it exists the CTA stays disabled
                  rather than writing a client-priced row. */}
              {offering.blocked ? (
                <div className="space-y-3">
                  <LockedAction label="Subscribe" reason={offering.blocked} />
                  {offering.href && (
                    <Button asChild variant="link" size="sm" className="h-auto p-0">
                      <Link to={offering.href}>
                        View my position
                        <ArrowUpRight aria-hidden="true" />
                      </Link>
                    </Button>
                  )}
                </div>
              ) : offering.href ? (
                <Button asChild size="sm">
                  <Link to={offering.href}>
                    Open
                    <ArrowUpRight aria-hidden="true" />
                  </Link>
                </Button>
              ) : null}
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Seed round tiers" description="Applies to both the open and private seed rounds.">
          <dl className="space-y-3">
            {SEED_TIERS.map((tier) => (
              <div key={tier.value} className="flex items-baseline justify-between gap-4 text-sm">
                <div>
                  <dt className="font-medium">{tier.label}</dt>
                  <dd className="text-xs text-muted-foreground">{tier.description}</dd>
                </div>
                <p className="tabular shrink-0 text-sm text-muted-foreground">
                  {tier.maxUsd === null
                    ? `${money(tier.minUsd, 'USD')}+`
                    : `${money(tier.minUsd, 'USD')} – ${money(tier.maxUsd, 'USD')}`}
                </p>
              </div>
            ))}
          </dl>
        </Section>

        <Section title="Seed round stages" description="Stage two carries shares only, with no STR entitlement.">
          <dl className="space-y-3">
            {SEED_STAGES.map((stage) => (
              <div key={stage.stage} className="space-y-0.5 text-sm">
                <dt className="font-medium">
                  Stage {stage.stage} · {stage.note}
                </dt>
                <dd className="text-xs text-muted-foreground">
                  {stage.window} · {stage.shares.toLocaleString('en-IE')} shares at{' '}
                  {money(stage.priceUsd, 'USD')}
                  {stage.strPerShare > 0 &&
                    ` · ${stage.strPerShare.toLocaleString('en-IE')} STR per share`}
                </dd>
              </div>
            ))}
          </dl>
        </Section>

        <Section
          title="STR IPO phases"
          description="The price steps up when a phase closes; the server prices each order at the phase live when it is created."
        >
          <dl className="space-y-3">
            {IPO_PHASES.map((phase) => {
              const closed = new Date(phase.endsAt) < new Date();
              return (
                <div key={phase.phase} className="flex items-baseline justify-between gap-4 text-sm">
                  <div>
                    <dt className="font-medium">{phase.label}</dt>
                    <dd className="text-xs text-muted-foreground">
                      Closes {shortDate(phase.endsAt)}
                    </dd>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <span className="tabular text-sm">${phase.pricePerStr.toFixed(3)} / STR</span>
                    {closed && <Badge tone="neutral">Closed</Badge>}
                  </div>
                </div>
              );
            })}
          </dl>
        </Section>
      </div>

      <Card className="mt-6">
        <CardContent className="flex gap-3">
          <ShieldCheck className="mt-0.5 size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
          <p className="text-sm text-muted-foreground">
            Nothing on these screens moves a balance. Subscriptions, credits and redemptions are
            settled by the server in a single statement, so two operations arriving together cannot
            overwrite one another, and no reference is ever invented to make a transfer look
            confirmed.
          </p>
        </CardContent>
      </Card>
    </>
  );
}
