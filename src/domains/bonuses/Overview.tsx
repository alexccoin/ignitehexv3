import { useMemo, useState } from 'react';
import { Clock, Gift, Sparkles, Wallet } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Stat } from '@/components/ui/stat';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { ChartLegend, CompositionChart, TrendChart } from '@/components/ui/charts';
import { shortDate, token as tokenAmount } from '@/lib/format';
import {
  creditedBySource,
  cumulativeByMonth,
  useRewardsSummary,
  type RewardsSummary,
} from './hooks';
import { REWARD_SOURCE_LABELS } from './constants';
import { Async, Detail, Pills, Section, amountLabel } from './shared';

/**
 * What the member has been given, across every programme that pays out.
 *
 * Two things this screen refuses to do, both of which v2 did:
 *
 *  - It does not add tokens of different kinds together. STR, CCOS, ARSS, wSTR
 *    and USD commissions are separate columns and separate charts. v2's
 *    referral page summed reward rows into a single "total earned" figure
 *    labelled wSTR regardless of what the rows actually held.
 *  - It does not quote a value for anything the server has not valued. A
 *    pending voucher shows as awaiting valuation, not as the package's list
 *    price, because the list price is not a promise anybody has made.
 */
export default function Overview() {
  const summary = useRewardsSummary();

  const creditedCount = summary.data?.events.filter((e) => e.status === 'credited').length ?? 0;
  const pendingCount = summary.data?.events.filter((e) => e.status === 'pending').length ?? 0;
  const wallet = summary.data?.arssWallet ?? null;

  return (
    <>
      <PageHeader
        title="Rewards"
        description="Vouchers, the airdrop, referrals and node rewards, in one ledger."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Credited"
          value={String(creditedCount)}
          sub="Rewards released to your account"
          loading={summary.isLoading}
          tone="success"
          icon={<Gift className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Awaiting release"
          value={String(pendingCount)}
          sub="Raised, not yet credited"
          loading={summary.isLoading}
          tone={pendingCount > 0 ? 'warning' : 'default'}
          icon={<Clock className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="ARSS balance"
          value={wallet ? tokenAmount(wallet.balance, 'arss') : '—'}
          sub={wallet ? `Updated ${shortDate(wallet.updatedAt)}` : 'No ARSS wallet yet'}
          loading={summary.isLoading}
          icon={<Wallet className="size-4" aria-hidden="true" />}
        />
        {/*
          Read straight from user_wallets.total_earned. v2 wrote this column as
          `arss_balance + amount` on every airdrop approval, which is not a
          lifetime total — it is the balance restated, so a second credit erased
          the first. Nothing in v3 computes it; if it looks wrong, the server
          wrote it wrong.
        */}
        <Stat
          label="ARSS lifetime earned"
          value={wallet ? tokenAmount(wallet.totalEarned, 'arss') : '—'}
          sub={wallet ? `${tokenAmount(wallet.totalSpent, 'arss')} spent` : 'Recorded server-side'}
          loading={summary.isLoading}
          icon={<Sparkles className="size-4" aria-hidden="true" />}
        />
      </div>

      <Async
        query={summary}
        isEmpty={(d) => d.events.length === 0}
        emptyTitle="No rewards yet"
        emptyDescription="Claim a voucher, register for the airdrop or share your referral link, and everything you are given will be listed here."
        skeleton={<Skeleton className="h-96 w-full" />}
      >
        {(data) => <Ledger data={data} />}
      </Async>
    </>
  );
}

/* ------------------------------------------------------------------------ */

function Ledger({ data }: { data: RewardsSummary }) {
  const tokens = useMemo(() => data.totals.map((t) => t.token), [data.totals]);
  const [picked, setPicked] = useState<string | null>(null);

  // The selection has to survive the data changing under it, so it is derived
  // rather than seeded from a first render that had no tokens in it.
  const selected = picked && tokens.includes(picked) ? picked : (tokens[0] ?? '');

  const trend = useMemo(() => cumulativeByMonth(data.events, selected), [data.events, selected]);
  const composition = useMemo(
    () => creditedBySource(data.events, selected, REWARD_SOURCE_LABELS),
    [data.events, selected]
  );

  const recent = data.events.slice(0, 12);

  return (
    <div className="space-y-6">
      <Section
        title="Credited over time"
        description="Cumulative, one token at a time. Amounts of different kinds are never added together."
        actions={
          tokens.length > 1 ? (
            <Pills
              options={tokens}
              value={selected}
              onChange={setPicked}
              label="Token"
              render={(t) => t.toUpperCase()}
            />
          ) : undefined
        }
      >
        <div className="grid gap-8 lg:grid-cols-2">
          <div className="space-y-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {selected.toUpperCase()} credited, running total
            </p>
            {trend.length > 0 ? (
              <TrendChart data={trend} format={(v) => amountLabel(selected, v)} height={220} />
            ) : (
              <EmptyState
                title="Nothing credited yet"
                description={`No ${selected.toUpperCase()} has been released to you so far.`}
              />
            )}
          </div>

          <div className="space-y-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Where it came from
            </p>
            {composition.length > 0 ? (
              <>
                <CompositionChart
                  data={composition}
                  format={(v) => amountLabel(selected, v)}
                  height={220}
                />
                <ChartLegend items={composition.map((c) => ({ label: c.label, index: c.index }))} />
              </>
            ) : (
              <EmptyState
                title="No breakdown yet"
                description="A composition appears once something has been credited."
              />
            )}
          </div>
        </div>
      </Section>

      <Section
        title="Earned by token"
        description="Credited is what you hold. Awaiting release is what the server has recorded but not yet paid."
        bodyClassName="p-0 pt-0"
      >
        <TableWrap>
          <Table>
            <THead>
              <TR>
                <TH>Token</TH>
                <TH className="text-right">Credited</TH>
                <TH className="text-right">Awaiting release</TH>
                <TH>Unvalued</TH>
              </TR>
            </THead>
            <TBody>
              {data.totals.map((t) => (
                <TR key={t.token}>
                  <TD className="font-medium uppercase">{t.token}</TD>
                  <TD className="tabular text-right">{amountLabel(t.token, t.earned)}</TD>
                  <TD className="tabular text-right text-muted-foreground">
                    {t.pending > 0 ? amountLabel(t.token, t.pending) : '—'}
                  </TD>
                  <TD>
                    {t.unvalued > 0 ? (
                      <Badge tone="warning">{t.unvalued} awaiting valuation</Badge>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </TableWrap>
      </Section>

      <Section title="Latest activity" bodyClassName="p-0 pt-0">
        <TableWrap>
          <Table>
            <THead>
              <TR>
                <TH>Date</TH>
                <TH>Source</TH>
                <TH>Detail</TH>
                <TH className="text-right">Amount</TH>
                <TH>Status</TH>
              </TR>
            </THead>
            <TBody>
              {recent.map((e) => (
                <TR key={e.id}>
                  <TD className="whitespace-nowrap text-muted-foreground">{shortDate(e.at)}</TD>
                  <TD>{REWARD_SOURCE_LABELS[e.source]}</TD>
                  {/* Verbatim: package labels are matched byte for byte server-side. */}
                  <TD className="max-w-72 truncate">{e.detail}</TD>
                  <TD className="tabular text-right">{amountLabel(e.token, e.amount)}</TD>
                  <TD>
                    <Badge
                      tone={
                        e.status === 'credited'
                          ? 'success'
                          : e.status === 'declined'
                            ? 'danger'
                            : 'warning'
                      }
                    >
                      {e.status === 'credited'
                        ? 'Credited'
                        : e.status === 'declined'
                          ? 'Declined'
                          : 'Awaiting release'}
                    </Badge>
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </TableWrap>
      </Section>

      {data.arssWallet && (
        <Section
          title="ARSS wallet"
          description="Figures as the server recorded them. Nothing on this screen recalculates them."
        >
          <div className="grid gap-5 sm:grid-cols-3">
            <Detail label="Balance" value={tokenAmount(data.arssWallet.balance, 'arss')} />
            <Detail label="Lifetime earned" value={tokenAmount(data.arssWallet.totalEarned, 'arss')} />
            <Detail label="Lifetime spent" value={tokenAmount(data.arssWallet.totalSpent, 'arss')} />
          </div>
        </Section>
      )}
    </div>
  );
}
