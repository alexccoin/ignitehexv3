import { useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Gavel, Lock, Receipt } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Field, Input } from '@/components/ui/input';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Table, TableWrap, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { relativeTime, shortDate, token as tokenAmount } from '@/lib/format';
import {
  useDomainListings,
  useListingBids,
  useMyBids,
  useMyEscrow,
  useMyTransactions,
  useSubmitPaymentReference,
  useUserId,
  useWithdrawBid,
  type MarketTxn,
} from './hooks';
import { BlockedAction, FormError, RowsSkeleton, Section, price } from './shared';

/** True while a reservation still has time on it. */
function isOpenForPayment(txn: MarketTxn): boolean {
  if (txn.escrow_status !== 'pending') return false;
  if (!txn.expires_at) return true;
  return new Date(txn.expires_at).getTime() > Date.now();
}

function BidsOnMyListings() {
  const myListings = useDomainListings('mine');
  const auctions = (myListings.data ?? []).filter(
    (l) => l.listing_type !== 'buy_now' && l.status === 'active'
  );
  const [selected, setSelected] = useState<string | null>(null);
  const bids = useListingBids(selected);

  if (myListings.isPending) return <RowsSkeleton rows={3} />;
  if (myListings.isError) {
    return <ErrorState error={myListings.error} onRetry={() => void myListings.refetch()} />;
  }
  if (auctions.length === 0) {
    return (
      <EmptyState
        icon={<Gavel className="size-5" />}
        title="No live auctions"
        description="Bids placed on domains you are auctioning show up here."
      />
    );
  }

  return (
    <div className="space-y-4 p-4">
      <Field label="Auction" htmlFor="auction-picker">
        <select
          id="auction-picker"
          className="flex h-9 w-full max-w-sm rounded-md border border-input bg-background px-3 text-sm"
          value={selected ?? ''}
          onChange={(e) => setSelected(e.target.value || null)}
        >
          <option value="">Select one of your auctions</option>
          {auctions.map((l) => (
            <option key={l.id} value={l.id}>
              {l.domain_name}.str
            </option>
          ))}
        </select>
      </Field>

      {selected &&
        (bids.isPending ? (
          <RowsSkeleton rows={3} />
        ) : bids.isError ? (
          <ErrorState error={bids.error} onRetry={() => void bids.refetch()} />
        ) : (bids.data ?? []).length === 0 ? (
          <EmptyState title="No bids yet" description="Nobody has bid on this auction." />
        ) : (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>Amount</TH>
                  <TH>Placed</TH>
                  <TH>Status</TH>
                  <TH>Decision</TH>
                </TR>
              </THead>
              <TBody>
                {(bids.data ?? []).map((bid) => (
                  <TR key={bid.id}>
                    <TD className="tabular font-medium">{price(bid.bid_amount, bid.currency)}</TD>
                    <TD className="text-muted-foreground">{relativeTime(bid.created_at)}</TD>
                    <TD>
                      <StatusBadge status={bid.status} />
                    </TD>
                    <TD>
                      {/*
                       * TODO(server): accepting a bid has to accept one row, reject
                       * every other bidder's row, close the listing and open the
                       * transaction — four writes, three of them on rows owned by
                       * other members. v2 fired them one after another
                       * (AcceptBidDialog.tsx:38-90); RLS silently dropped the writes
                       * to other bidders' rows, so losing bidders stayed "pending"
                       * forever, and a failure at the last step left an accepted bid
                       * with no transaction behind it. Needs
                       * `accept_domain_bid(p_listing_id, p_bid_id)` as a single
                       * service-role RPC.
                       */}
                      <BlockedAction
                        label="Accept"
                        reason="Accepting a bid changes rows belonging to other bidders and must happen in one server-side transaction. Doing it here would leave losing bids pending and could accept a bid with no order behind it."
                      />
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          </TableWrap>
        ))}
    </div>
  );
}

export default function Activity() {
  const userId = useUserId();
  const txns = useMyTransactions();
  const bids = useMyBids();
  const escrow = useMyEscrow();
  const withdraw = useWithdrawBid();
  const submitReference = useSubmitPaymentReference();

  const [payingFor, setPayingFor] = useState<string | null>(null);
  const [reference, setReference] = useState('');

  const escrowRows = escrow.data ?? [];
  const locked = escrowRows.filter((e) => e.status === 'locked');
  const openOrders = (txns.data ?? []).filter((t) => t.buyer_id === userId && isOpenForPayment(t));

  const submit = (transactionId: string) => {
    submitReference.mutate(
      { transactionId, reference },
      {
        onSuccess: () => {
          toast.success('Payment reference recorded. An operator will verify it.');
          setPayingFor(null);
          setReference('');
        },
      }
    );
  };

  return (
    <>
      <PageHeader
        title="Activity"
        description="Your orders, bids and anything held in marketplace escrow."
        actions={
          <Button asChild variant="ghost">
            <Link to="/marketplace">Back to listings</Link>
          </Button>
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Stat
          label="Open orders"
          value={openOrders.length}
          icon={<Receipt className="size-4" />}
          sub="Awaiting your payment reference"
          loading={txns.isPending}
        />
        <Stat
          label="Active bids"
          value={(bids.data ?? []).filter((b) => b.status === 'pending').length}
          icon={<Gavel className="size-4" />}
          loading={bids.isPending}
        />
        <Stat
          label="Positions in escrow"
          value={locked.length}
          icon={<Lock className="size-4" />}
          tone={locked.length > 0 ? 'warning' : 'default'}
          loading={escrow.isPending}
        />
      </div>

      <div className="space-y-8">
        <Section title="Orders" description="Domain purchases you have started or received.">
          <Card>
            {txns.isPending ? (
              <RowsSkeleton />
            ) : txns.isError ? (
              <ErrorState error={txns.error} onRetry={() => void txns.refetch()} />
            ) : (txns.data ?? []).length === 0 ? (
              <EmptyState
                icon={<Receipt className="size-5" />}
                title="No orders"
                description="Reserving a buy-now listing opens an order here."
                action={
                  <Button asChild size="sm" variant="secondary">
                    <Link to="/marketplace">Browse listings</Link>
                  </Button>
                }
              />
            ) : (
              <>
                <FormError error={submitReference.error} />
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Side</TH>
                        <TH>Price</TH>
                        <TH>Type</TH>
                        <TH>Escrow</TH>
                        <TH>Reference</TH>
                        <TH>Expires</TH>
                        <TH>Actions</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {(txns.data ?? []).map((txn) => (
                        <TR key={txn.id}>
                          <TD>
                            <Badge tone={txn.buyer_id === userId ? 'primary' : 'neutral'}>
                              {txn.buyer_id === userId ? 'Buying' : 'Selling'}
                            </Badge>
                          </TD>
                          <TD className="tabular font-medium">
                            {price(txn.sale_price, txn.currency)}
                          </TD>
                          <TD className="text-muted-foreground">{txn.sale_type}</TD>
                          <TD>
                            <StatusBadge status={txn.escrow_status} />
                          </TD>
                          <TD className="font-mono text-xs">
                            {txn.transaction_hash ? (
                              `${txn.transaction_hash.slice(0, 12)}…`
                            ) : (
                              <span className="font-sans text-muted-foreground">Not submitted</span>
                            )}
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(txn.expires_at)}</TD>
                          <TD>
                            {txn.buyer_id === userId && isOpenForPayment(txn) ? (
                              payingFor === txn.id ? (
                                <div className="flex items-center gap-2">
                                  <Input
                                    aria-label="Payment transaction reference"
                                    className="h-8 w-48"
                                    value={reference}
                                    onChange={(e) => setReference(e.target.value)}
                                    placeholder="Transaction reference"
                                  />
                                  <Button
                                    size="sm"
                                    disabled={submitReference.isPending || reference.trim().length < 8}
                                    onClick={() => submit(txn.id)}
                                  >
                                    Save
                                  </Button>
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    onClick={() => {
                                      setPayingFor(null);
                                      setReference('');
                                    }}
                                  >
                                    Cancel
                                  </Button>
                                </div>
                              ) : (
                                <Button
                                  size="sm"
                                  variant="secondary"
                                  onClick={() => {
                                    setPayingFor(txn.id);
                                    setReference('');
                                  }}
                                >
                                  Add payment reference
                                </Button>
                              )
                            ) : (
                              <span className="text-muted-foreground">—</span>
                            )}
                          </TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              </>
            )}
          </Card>
        </Section>

        <Section title="Your bids">
          <Card>
            {bids.isPending ? (
              <RowsSkeleton />
            ) : bids.isError ? (
              <ErrorState error={bids.error} onRetry={() => void bids.refetch()} />
            ) : (bids.data ?? []).length === 0 ? (
              <EmptyState
                icon={<Gavel className="size-5" />}
                title="No bids"
                description="Bids you place on domain auctions appear here."
              />
            ) : (
              <>
                <FormError error={withdraw.error} />
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Amount</TH>
                        <TH>Status</TH>
                        <TH>Winning</TH>
                        <TH>Placed</TH>
                        <TH>Actions</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {(bids.data ?? []).map((bid) => (
                        <TR key={bid.id}>
                          <TD className="tabular font-medium">
                            {price(bid.bid_amount, bid.currency)}
                          </TD>
                          <TD>
                            <StatusBadge status={bid.status} />
                          </TD>
                          <TD>
                            {bid.is_winning_bid ? (
                              <Badge tone="success">Leading</Badge>
                            ) : (
                              <span className="text-muted-foreground">—</span>
                            )}
                          </TD>
                          <TD className="text-muted-foreground">{relativeTime(bid.created_at)}</TD>
                          <TD>
                            {bid.status === 'pending' ? (
                              <Button
                                size="sm"
                                variant="ghost"
                                disabled={withdraw.isPending}
                                onClick={() =>
                                  withdraw.mutate(bid.id, {
                                    onSuccess: () => toast.success('Bid withdrawn.'),
                                  })
                                }
                              >
                                Withdraw
                              </Button>
                            ) : (
                              <span className="text-muted-foreground">—</span>
                            )}
                          </TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              </>
            )}
          </Card>
        </Section>

        <Section
          title="Bids on your auctions"
          description="Read-only until bid acceptance runs as one server-side transaction."
        >
          <Card>
            <BidsOnMyListings />
          </Card>
        </Section>

        <Section
          title="Escrow"
          description="Tokens locked against a listing. These are not in your spendable balance."
        >
          <Card>
            {escrow.isPending ? (
              <RowsSkeleton rows={3} />
            ) : escrow.isError ? (
              <ErrorState error={escrow.error} onRetry={() => void escrow.refetch()} />
            ) : escrowRows.length === 0 ? (
              <EmptyState
                icon={<Lock className="size-5" />}
                title="Nothing in escrow"
                description="Listing tokens for sale moves them here until the listing settles."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Asset</TH>
                      <TH>Amount</TH>
                      <TH>Status</TH>
                      <TH>Locked</TH>
                      <TH>Released</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {escrowRows.map((row) => (
                      <TR key={row.id}>
                        <TD className="font-medium">{row.asset_symbol}</TD>
                        <TD className="tabular">{tokenAmount(row.amount, row.asset_symbol)}</TD>
                        <TD>
                          <Badge tone={row.status === 'locked' ? 'warning' : 'neutral'}>
                            {row.status}
                          </Badge>
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                        <TD className="text-muted-foreground">{shortDate(row.released_at)}</TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Card>
        </Section>
      </div>
    </>
  );
}
