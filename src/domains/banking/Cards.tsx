import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { CreditCard, Loader2, Network, Plus } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { useIbans } from '@/hooks/data';
import { maskIban, money, shortDate } from '@/lib/format';
import {
  useBankApplication,
  useBankingProfile,
  useCardApplications,
  useNetworkCard,
  useNetworkTransactions,
  usePrepaidCards,
  useStrDomains,
  useSubmitCardApplication,
  useSubmitCardTopUp,
} from './hooks';
import { AsyncSection, ApprovalGate, Metric, SelectInput, ServerActionPending } from './shared';

function errorMessage(err: unknown, fallback: string) {
  return err instanceof Error ? err.message : fallback;
}

export default function Cards() {
  const application = useBankApplication();
  const profile = useBankingProfile();
  const networkCard = useNetworkCard();
  const cards = usePrepaidCards();
  const cardApplications = useCardApplications();
  const domains = useStrDomains();
  const ibans = useIbans();
  const networkTxns = useNetworkTransactions(networkCard.data?.id, 10);

  const applyForCard = useSubmitCardApplication();
  const topUp = useSubmitCardTopUp();

  const [domainId, setDomainId] = useState('');
  const [topUpCard, setTopUpCard] = useState('');
  const [topUpIban, setTopUpIban] = useState('');
  const [topUpAmount, setTopUpAmount] = useState('');

  const gateLoading = application.isLoading || profile.isLoading;
  const approved = application.data?.status === 'approved' || !!profile.data;

  /**
   * submit-card-topup identifies the source account by its plaintext IBAN, so
   * an account whose row has been encrypted cannot be offered — the column the
   * browser can read holds '***ENCRYPTED***' after the validate_iban_or_mask
   * trigger. See the TODO at the bottom of this page.
   */
  const selectableIbans = useMemo(
    () =>
      (ibans.data ?? []).filter(
        (i) => i.status === 'active' && !i.is_data_encrypted && i.iban !== '***ENCRYPTED***'
      ),
    [ibans.data]
  );

  const encryptedIbanCount = (ibans.data ?? []).length - selectableIbans.length;

  const loadableCards = useMemo(() => {
    const list = (cards.data ?? [])
      .filter((c) => c.status === 'active' && c.full_identifier)
      .map((c) => ({
        identifier: c.full_identifier!,
        label: (c.masked_card ?? c.full_identifier!) + ' · ' + c.currency,
        currency: c.currency,
      }));

    if (networkCard.data?.status === 'active') {
      list.unshift({
        identifier: networkCard.data.card_number,
        label: networkCard.data.card_number + ' · network card',
        currency: 'EUR',
      });
    }
    return list;
  }, [cards.data, networkCard.data]);

  const pendingCardApplication = (cardApplications.data ?? []).some((a) => a.status === 'pending');
  const eligibleDomains = (domains.data ?? []).filter((d) => d.status === 'active');

  async function submitCardApplication() {
    const domain = eligibleDomains.find((d) => d.id === domainId);
    if (!domain) {
      toast.error('Choose an STR domain to issue the card against.');
      return;
    }

    try {
      await applyForCard.mutateAsync({ domainId: domain.id, domainName: domain.domain_name });
      toast.success('Card application submitted for review.');
      setDomainId('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not submit the card application'));
    }
  }

  async function submitTopUp() {
    // Selected by row id, not by IBAN: the account number should not sit in a
    // DOM attribute just to identify which account the member picked.
    const source = selectableIbans.find((i) => i.id === topUpIban);
    const card = loadableCards.find((c) => c.identifier === topUpCard);
    const amount = Number(topUpAmount);

    if (!card) {
      toast.error('Choose a card to load.');
      return;
    }
    if (!source) {
      toast.error('Choose a source account.');
      return;
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      toast.error('Enter an amount greater than zero.');
      return;
    }

    try {
      const result = await topUp.mutateAsync({
        sourceIban: source.iban,
        sourceCurrency: source.currency,
        cardIdentifier: card.identifier,
        amount,
        currency: card.currency,
      });
      toast.success('Top-up submitted for approval.', {
        description:
          money(amount, card.currency) +
          ' to ' +
          card.identifier +
          ' · CCOS fee ' +
          String(result.fee?.fee_ccos ?? 0.2),
      });
      setTopUpAmount('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not submit the top-up'));
    }
  }

  return (
    <>
      <PageHeader
        title="Cards"
        description="CCoin network card, prepaid cards and card funding."
      />

      {gateLoading ? (
        <Skeleton className="h-48 w-full" />
      ) : !approved ? (
        <ApprovalGate status={application.data?.status} />
      ) : (
        <div className="space-y-6">
          {/* Network card */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="flex items-center gap-2">
                  <Network className="size-4 text-primary" />
                  CCoin network card
                </CardTitle>
                <CardDescription>
                  Issued against an STR domain and settled on the CCoin network.
                </CardDescription>
              </div>
              {networkCard.data && <StatusBadge status={networkCard.data.status} />}
            </CardHeader>
            <CardContent>
              {networkCard.isLoading ? (
                <Skeleton className="h-28 w-full" />
              ) : networkCard.data ? (
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <Metric
                    label="Card number"
                    value={<span className="font-mono text-sm">{networkCard.data.card_number}</span>}
                  />
                  <Metric
                    label="Internal IBAN"
                    value={
                      <span className="font-mono text-sm">
                        {maskIban(networkCard.data.internal_iban)}
                      </span>
                    }
                  />
                  <Metric label="STR domain" value={networkCard.data.str_domain} />
                  <Metric
                    label="Issued"
                    value={shortDate(networkCard.data.issued_at)}
                    hint={
                      networkCard.data.last_activity
                        ? 'Last activity ' + shortDate(networkCard.data.last_activity)
                        : 'No activity yet'
                    }
                  />
                </div>
              ) : (
                <div className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    No network card on this account yet. Apply against an STR domain you hold — an
                    administrator issues the card through the CCoin network.
                  </p>

                  {domains.isLoading ? (
                    <Skeleton className="h-9 w-full max-w-sm" />
                  ) : eligibleDomains.length === 0 ? (
                    <p className="text-sm text-muted-foreground">
                      You need an active STR domain before a card can be issued.
                    </p>
                  ) : pendingCardApplication ? (
                    <Badge tone="warning">Application under review</Badge>
                  ) : (
                    <div className="flex flex-wrap items-end gap-3">
                      <div className="w-full max-w-xs">
                        <Field label="STR domain" htmlFor="card-domain">
                          <SelectInput
                            id="card-domain"
                            value={domainId}
                            onChange={(e) => setDomainId(e.target.value)}
                          >
                            <option value="">Choose a domain</option>
                            {eligibleDomains.map((d) => (
                              <option key={d.id} value={d.id}>
                                {d.domain_name}
                              </option>
                            ))}
                          </SelectInput>
                        </Field>
                      </div>
                      <Button
                        onClick={() => void submitCardApplication()}
                        disabled={applyForCard.isPending || !domainId}
                      >
                        {applyForCard.isPending ? <Loader2 className="animate-spin" /> : <Plus />}
                        Apply for a card
                      </Button>
                    </div>
                  )}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Card applications */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Card applications</CardTitle>
                <CardDescription>Requests waiting on an administrator.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={cardApplications}
                emptyTitle="No card applications"
                emptyDescription="Applications you submit appear here with their decision."
                skeletonClassName="mx-5 h-28"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Domain</TH>
                          <TH>Submitted</TH>
                          <TH>Decided</TH>
                          <TH>Notes</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((row) => (
                          <TR key={row.id}>
                            <TD className="font-mono text-xs">{row.str_domain_name}</TD>
                            <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                            <TD className="text-muted-foreground">{shortDate(row.processed_at)}</TD>
                            <TD className="max-w-xs truncate text-muted-foreground">
                              {row.admin_notes ?? '—'}
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
              </AsyncSection>
            </CardContent>
          </Card>

          {/* Prepaid cards */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="flex items-center gap-2">
                  <CreditCard className="size-4 text-muted-foreground" />
                  Prepaid cards
                </CardTitle>
                <CardDescription>Card numbers are stored and shown masked.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={cards}
                emptyTitle="No cards issued"
                emptyDescription="Cards appear here once an administrator issues them."
                skeletonClassName="mx-5 h-32"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Card</TH>
                          <TH>Network</TH>
                          <TH>Type</TH>
                          <TH className="text-right">Balance</TH>
                          <TH>Expiry</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((card) => (
                          <TR key={card.id}>
                            <TD className="font-mono text-xs">
                              {card.masked_card ?? '•••• ' + card.card_last4}
                            </TD>
                            <TD className="uppercase">{card.network}</TD>
                            <TD className="text-muted-foreground">
                              {card.card_type}
                              {card.physical_card ? ' · physical' : ' · virtual'}
                            </TD>
                            <TD className="tabular text-right">
                              {money(Number(card.balance ?? 0), card.currency)}
                            </TD>
                            <TD className="text-muted-foreground">
                              {card.expiry_date ?? '—'}
                            </TD>
                            <TD>
                              <StatusBadge status={card.card_status ?? card.status} />
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

          {/* Load a card */}
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Load a card</CardTitle>
                <CardDescription>
                  Submitted as pending. The debit, the CCOS fee and the treasury hold are all
                  applied by submit-card-topup — never by this page.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              {cards.isLoading || ibans.isLoading || networkCard.isLoading ? (
                <Skeleton className="h-32 w-full" />
              ) : loadableCards.length === 0 || selectableIbans.length === 0 ? (
                <p className="text-sm text-muted-foreground">
                  {loadableCards.length === 0
                    ? 'You need an active card before it can be loaded.'
                    : 'No account can be used as a source. Every active account on this profile is encrypted, and the top-up function identifies the source by its plaintext IBAN.'}
                </p>
              ) : (
                <>
                  <div className="grid gap-4 md:grid-cols-3">
                    <Field label="Card" htmlFor="topup-card">
                      <SelectInput
                        id="topup-card"
                        value={topUpCard}
                        onChange={(e) => setTopUpCard(e.target.value)}
                      >
                        <option value="">Choose a card</option>
                        {loadableCards.map((c) => (
                          <option key={c.identifier} value={c.identifier}>
                            {c.label}
                          </option>
                        ))}
                      </SelectInput>
                    </Field>

                    <Field
                      label="Source account"
                      htmlFor="topup-iban"
                      hint={
                        encryptedIbanCount > 0
                          ? encryptedIbanCount + ' encrypted account(s) cannot be used as a source'
                          : undefined
                      }
                    >
                      <SelectInput
                        id="topup-iban"
                        value={topUpIban}
                        onChange={(e) => setTopUpIban(e.target.value)}
                      >
                        <option value="">Choose an account</option>
                        {selectableIbans.map((i) => (
                          <option key={i.id} value={i.id}>
                            {i.currency + ' · ' + maskIban(i.iban)}
                          </option>
                        ))}
                      </SelectInput>
                    </Field>

                    <Field label="Amount" htmlFor="topup-amount" hint="A 0.2 CCOS fee applies.">
                      <Input
                        id="topup-amount"
                        type="number"
                        min="0"
                        step="0.01"
                        placeholder="0.00"
                        value={topUpAmount}
                        onChange={(e) => setTopUpAmount(e.target.value)}
                      />
                    </Field>
                  </div>

                  <Button onClick={() => void submitTopUp()} disabled={topUp.isPending}>
                    {topUp.isPending ? <Loader2 className="animate-spin" /> : <CreditCard />}
                    Submit top-up
                  </Button>
                </>
              )}
            </CardContent>
          </Card>

          {/* Network activity */}
          {networkCard.data && (
            <Card>
              <CardHeader>
                <div className="space-y-1">
                  <CardTitle>Network card activity</CardTitle>
                  <CardDescription>Validated movements on the CCoin network.</CardDescription>
                </div>
              </CardHeader>
              <CardContent className="p-0 pb-2">
                <AsyncSection
                  query={networkTxns}
                  emptyTitle="No activity yet"
                  emptyDescription="Transactions appear once the card is used."
                  skeletonClassName="mx-5 h-32"
                >
                  {(rows) => (
                    <TableWrap>
                      <Table>
                        <THead>
                          <TR>
                            <TH>Date</TH>
                            <TH>Type</TH>
                            <TH>Counterparty</TH>
                            <TH className="text-right">Amount</TH>
                            <TH>Status</TH>
                          </TR>
                        </THead>
                        <TBody>
                          {rows.map((txn) => (
                            <TR key={txn.id}>
                              <TD className="text-muted-foreground">{shortDate(txn.created_at)}</TD>
                              <TD className="capitalize">{txn.transaction_type}</TD>
                              <TD className="max-w-[12rem] truncate font-mono text-xs">
                                {txn.to_address}
                              </TD>
                              <TD className="tabular text-right">
                                {money(Number(txn.amount), txn.currency)}
                              </TD>
                              <TD>
                                <StatusBadge status={txn.status} />
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
          )}

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Card operations</CardTitle>
                <CardDescription>
                  Offered only once a function exists to carry them out safely.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-3">
              <ServerActionPending
                label="Freeze or unfreeze a card"
                todo="No edge function covers card status. Flipping prepaid_cards.card_status from the browser would let anyone who can reach the table unfreeze a card an administrator froze."
              />
              <ServerActionPending
                label="Order a physical card"
                todo="v2 collected a shipping address in CardShippingDialog and wrote it straight to the table. A function is needed to validate the address, price the shipping and record consent to share it with the fulfilment partner."
              />
              <ServerActionPending
                label="Top up from an encrypted account"
                todo="submit-card-topup identifies the source by plaintext IBAN, which is unreadable once is_data_encrypted is set. The function needs to accept an iban_accounts.id and resolve the account server-side."
              />
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
