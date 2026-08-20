import { Link } from 'react-router-dom';
import {
  ArrowLeftRight,
  Banknote,
  Building2,
  CreditCard,
  ExternalLink,
  Globe,
  Landmark,
  Receipt,
  Send,
  ShieldCheck,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { useFiatWallets, useIbans } from '@/hooks/data';
import { money, token, shortDate, maskIban } from '@/lib/format';
import {
  useBankApplication,
  useBankingProfile,
  useLedgerEntries,
  useNetworkCard,
  usePendingTreasuryTransfers,
  usePrepaidCards,
} from './hooks';
import { AsyncSection, ApprovalGate } from './shared';

const HEADLINE_CURRENCIES = ['EUR', 'CHF', 'GBP'] as const;

const QUICK_ACTIONS = [
  { to: '/banking/transfers', label: 'Send & swap', hint: 'Move fiat, swap rails', icon: Send },
  { to: '/banking/accounts', label: 'Accounts', hint: 'IBANs and balances', icon: Building2 },
  { to: '/banking/cards', label: 'Cards', hint: 'Issue and load', icon: CreditCard },
  { to: '/banking/transfers', label: 'History', hint: 'Settled movements', icon: Receipt },
] as const;

export default function BankOverview() {
  const application = useBankApplication();
  const profile = useBankingProfile();
  const wallets = useFiatWallets();
  const ibans = useIbans();
  const pending = usePendingTreasuryTransfers();
  const ledger = useLedgerEntries(8);
  const cards = usePrepaidCards();
  const networkCard = useNetworkCard();

  const gateLoading = application.isLoading || profile.isLoading;
  const approved = application.data?.status === 'approved' || !!profile.data;

  // Balances are never summed across currencies. v2 added EUR, CHF and GBP
  // together and printed the result with a € sign, which was simply wrong.
  const balanceByCurrency = new Map<string, number>();
  for (const w of wallets.data ?? []) {
    balanceByCurrency.set(
      w.currency,
      (balanceByCurrency.get(w.currency) ?? 0) + Number(w.balance ?? 0)
    );
  }

  const headline = HEADLINE_CURRENCIES.reduce(
    (best, cur) => ((balanceByCurrency.get(cur) ?? 0) > best.amount
      ? { currency: cur as string, amount: balanceByCurrency.get(cur) ?? 0 }
      : best),
    { currency: 'EUR', amount: balanceByCurrency.get('EUR') ?? 0 }
  );

  const ibanFor = (currency: string) => (ibans.data ?? []).find((i) => i.currency === currency);
  const pendingCcos = (pending.data ?? []).reduce((s, r) => s + Number(r.fee_ccos ?? 0), 0);
  const activeCards = (cards.data ?? []).filter((c) => c.status === 'active').length;

  return (
    <>
      <PageHeader
        title="CCoin Bank"
        description="Sovereign on-chain private banking — multi-currency IBANs, cards and settlement."
        actions={
          profile.data?.banking_status ? (
            <StatusBadge status={profile.data.banking_status} />
          ) : application.data ? (
            <StatusBadge status={application.data.status} />
          ) : null
        }
      />

      {gateLoading ? (
        <div className="space-y-4">
          <Skeleton className="h-48 w-full" />
          <Skeleton className="h-24 w-full" />
        </div>
      ) : !approved ? (
        <ApprovalGate status={application.data?.status} />
      ) : (
        <div className="space-y-6">
          {/* Hero bento: the headline balance beside a per-currency stack. The
              v2 page put these two together and it was the right call — one
              figure to read, and the accounts that make it up next to it. */}
          <div className="grid gap-4 lg:grid-cols-12">
            <Card className="relative overflow-hidden lg:col-span-8">
              <div className="brand-gradient pointer-events-none absolute inset-x-0 top-0 h-1" />
              <CardContent className="flex flex-wrap items-start justify-between gap-6 p-6">
                <div className="min-w-0">
                  <Badge tone="primary">
                    <Banknote className="size-3" />
                    {headline.currency} balance
                  </Badge>

                  {wallets.isLoading ? (
                    <Skeleton className="mt-4 h-12 w-64" />
                  ) : (
                    <p className="tabular mt-4 text-3xl font-semibold">
                      {money(headline.amount, headline.currency)}
                    </p>
                  )}

                  <p className="mt-2 text-sm text-muted-foreground">
                    Across {(wallets.data ?? []).length} currency{' '}
                    {(wallets.data ?? []).length === 1 ? 'account' : 'accounts'}. Currencies are
                    shown separately — nothing is converted for display.
                  </p>

                  <div className="mt-5 flex flex-wrap gap-2">
                    <Button asChild size="sm">
                      <Link to="/banking/transfers">
                        <Send />
                        Send money
                      </Link>
                    </Button>
                    <Button asChild size="sm" variant="secondary">
                      <Link to="/banking/transfers">
                        <ArrowLeftRight />
                        Swap
                      </Link>
                    </Button>
                    <Button asChild size="sm" variant="secondary">
                      <Link to="/banking/cards">
                        <CreditCard />
                        Cards
                      </Link>
                    </Button>
                  </div>
                </div>

                <div className="hidden size-24 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary md:flex">
                  <Landmark className="size-10" />
                </div>
              </CardContent>
            </Card>

            <Card className="lg:col-span-4">
              <CardHeader className="pb-0">
                <CardTitle className="text-base">Accounts</CardTitle>
                <Button asChild size="sm" variant="ghost">
                  <Link to="/banking/accounts">View all</Link>
                </Button>
              </CardHeader>
              <CardContent className="space-y-2 pt-3">
                {wallets.isLoading || ibans.isLoading ? (
                  <Skeleton className="h-36 w-full" />
                ) : (
                  HEADLINE_CURRENCIES.map((cur) => {
                    const account = ibanFor(cur);
                    return (
                      <div
                        key={cur}
                        className="flex items-center justify-between gap-3 rounded-lg border border-border p-3"
                      >
                        <div className="min-w-0">
                          <p className="text-xs uppercase tracking-wide text-muted-foreground">
                            {cur} account
                          </p>
                          <p className="tabular text-base font-semibold">
                            {money(balanceByCurrency.get(cur) ?? 0, cur)}
                          </p>
                        </div>
                        {account ? (
                          <StatusBadge status={account.status} />
                        ) : (
                          <Badge tone="neutral">Not opened</Badge>
                        )}
                      </div>
                    );
                  })
                )}
              </CardContent>
            </Card>
          </div>

          {/* Quick actions */}
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {QUICK_ACTIONS.map(({ to, label, hint, icon: Icon }) => (
              <Link
                key={label}
                to={to}
                className="panel flex items-center gap-3 p-4 transition-colors hover:bg-elevated"
              >
                <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                  <Icon className="size-5" />
                </span>
                <span className="min-w-0">
                  <span className="block text-sm font-semibold">{label}</span>
                  <span className="block truncate text-xs text-muted-foreground">{hint}</span>
                </span>
              </Link>
            ))}
          </div>

          {/* Headline figures */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat
              label="Bank accounts"
              value={String((ibans.data ?? []).length)}
              sub="IBANs opened"
              icon={<Building2 className="size-4" />}
              loading={ibans.isLoading}
            />
            <Stat
              label="Active cards"
              value={String(activeCards)}
              sub={networkCard.data ? 'Network card issued' : 'No network card'}
              icon={<CreditCard className="size-4" />}
              loading={cards.isLoading || networkCard.isLoading}
            />
            <Stat
              label="Awaiting approval"
              value={String((pending.data ?? []).length)}
              sub="Held in treasury"
              tone={(pending.data ?? []).length > 0 ? 'warning' : 'default'}
              icon={<ShieldCheck className="size-4" />}
              loading={pending.isLoading}
            />
            <Stat
              label="CCOS fees captured"
              value={token(pendingCcos, 'ccos')}
              sub="On pending movements"
              icon={<Receipt className="size-4" />}
              loading={pending.isLoading}
            />
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle>Awaiting approval</CardTitle>
                  <CardDescription>
                    Transfers and swaps held in treasury until an admin releases them.
                  </CardDescription>
                </div>
              </CardHeader>
              <CardContent className="p-0 pb-2">
                <AsyncSection
                  query={pending}
                  emptyTitle="Nothing pending"
                  emptyDescription="Every movement on this account has settled."
                  skeletonClassName="mx-5 h-40"
                >
                  {(rows) => (
                    <TableWrap>
                      <Table>
                        <THead>
                          <TR>
                            <TH>Rail</TH>
                            <TH>Destination</TH>
                            <TH className="text-right">Amount</TH>
                            <TH className="text-right">CCOS fee</TH>
                            <TH>Status</TH>
                          </TR>
                        </THead>
                        <TBody>
                          {rows.map((r) => (
                            <TR key={r.id}>
                              <TD className="font-medium uppercase">
                                {r.rail ?? r.transfer_type}
                              </TD>
                              <TD className="max-w-[14rem] truncate text-muted-foreground">
                                {r.to_identifier}
                              </TD>
                              <TD className="tabular text-right">
                                {money(Number(r.amount), r.currency)}
                              </TD>
                              <TD className="tabular text-right text-warning">
                                {token(Number(r.fee_ccos ?? 0), 'ccos')}
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
                </AsyncSection>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle>Network ledger</CardTitle>
                  <CardDescription>Settlement entries written to the CCoin ledger.</CardDescription>
                </div>
              </CardHeader>
              <CardContent className="p-0 pb-2">
                <AsyncSection
                  query={ledger}
                  emptyTitle="No ledger entries"
                  emptyDescription="Settled movements appear here once the network validates them."
                  skeletonClassName="mx-5 h-40"
                >
                  {(rows) => (
                    <TableWrap>
                      <Table>
                        <THead>
                          <TR>
                            <TH>Date</TH>
                            <TH>Counterparty</TH>
                            <TH className="text-right">Amount</TH>
                            <TH>Status</TH>
                          </TR>
                        </THead>
                        <TBody>
                          {rows.map((r) => (
                            <TR key={r.id}>
                              <TD className="text-muted-foreground">{shortDate(r.created_at)}</TD>
                              <TD className="max-w-[12rem] truncate font-mono text-xs">
                                {r.to_identifier}
                              </TD>
                              <TD className="tabular text-right">
                                {money(Number(r.amount), r.currency)}
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
                </AsyncSection>
              </CardContent>
            </Card>
          </div>

          {/* Onshore vs offshore, the split v2 expressed through DomeSection. */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Banking modes</CardTitle>
                <CardDescription>
                  Onshore settles here under CCoin Bank. Offshore extends the same identity to
                  ccoin.finance.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="grid gap-4 md:grid-cols-2">
              <div className="rounded-lg border border-border p-4">
                <div className="flex items-center gap-2">
                  <Landmark className="size-4 text-primary" />
                  <p className="font-medium">Onshore — CCoin Bank</p>
                  <Badge tone="success">Active</Badge>
                </div>
                <p className="mt-2 text-sm text-muted-foreground">
                  Licensed EUR, CHF and GBP accounts with SEPA, SWIFT and UK rails. Card issuance
                  and settlement run through this app.
                </p>
                {profile.data?.str_domain && (
                  <p className="mt-3 font-mono text-xs text-muted-foreground">
                    Identity: {profile.data.str_domain}
                  </p>
                )}
                {ibanFor('EUR') && (
                  <p className="mt-1 font-mono text-xs text-muted-foreground">
                    Primary: {maskIban(ibanFor('EUR')?.iban)}
                  </p>
                )}
              </div>

              <div className="rounded-lg border border-border p-4">
                <div className="flex items-center gap-2">
                  <Globe className="size-4 text-accent" />
                  <p className="font-medium">Offshore — CCoin Finance</p>
                  <Badge tone="info">External</Badge>
                </div>
                <p className="mt-2 text-sm text-muted-foreground">
                  Global Visa cards across 195+ jurisdictions, 30+ fiat and 20+ crypto rails, under
                  the same profile. Held and operated at ccoin.finance.
                </p>
                <Button asChild size="sm" variant="secondary" className="mt-3">
                  <a href="https://ccoin.finance" target="_blank" rel="noreferrer noopener">
                    Open ccoin.finance
                    <ExternalLink />
                  </a>
                </Button>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
