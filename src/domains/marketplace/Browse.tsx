import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Gavel, Globe, Coins, Search, Store, Timer } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Stat } from '@/components/ui/stat';
import { Input, Field } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Table, TableWrap, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { relativeTime, shortDate, token as tokenAmount } from '@/lib/format';
import {
  useDomainListings,
  useMarketplaceStats,
  usePlaceBid,
  useReserveListing,
  useTokenListings,
  useUserId,
  type DomainListing,
} from './hooks';
import { BlockedAction, FormError, Modal, RowsSkeleton, Section, Tabs, price } from './shared';

const RESERVATION_HOURS = 6;

const DOMAIN_TYPES = [
  { value: 'all', label: 'All' },
  { value: 'personal', label: 'Personal' },
  { value: 'business', label: 'Business' },
  { value: 'premium', label: 'Premium' },
  { value: 'brand', label: 'Brand' },
];

/**
 * The address a buyer should pay for THIS listing's currency, or null.
 *
 * The match is strict on currency. Falling back to whichever address happens to
 * be populated would show an ETH address next to a BTC price — money sent to
 * the wrong chain is money gone.
 */
function payoutAddress(listing: DomainListing): string | null {
  const currency = listing.currency?.toUpperCase();
  const declared = listing.seller_wallet_currency?.toUpperCase();
  if (currency === 'ETH') return listing.seller_eth_wallet ?? (declared === 'ETH' ? listing.seller_wallet_address : null);
  if (declared && declared === currency) return listing.seller_wallet_address;
  return null;
}

function DomainCard({
  listing,
  isMine,
  onReserve,
  onBid,
}: {
  listing: DomainListing;
  isMine: boolean;
  onReserve: (listing: DomainListing) => void;
  onBid: (listing: DomainListing) => void;
}) {
  const isAuction = listing.listing_type !== 'buy_now';
  const headline = isAuction
    ? (listing.current_bid ?? listing.starting_bid)
    : listing.buy_now_price;

  return (
    <Card className="group flex flex-col justify-between overflow-hidden p-0 transition-all duration-200 hover:-translate-y-1 hover:border-primary/40">
      {/* A domain has no artwork, so the tile is generated from the name: the
          brand wash plus its initial. It gives the grid the visual rhythm a
          marketplace needs without inventing imagery that isn't there. */}
      <div className="brand-gradient relative flex h-32 items-center justify-center">
        <span className="font-display text-4xl font-extrabold uppercase text-white/95">
          {listing.domain_name?.[0] ?? '?'}
        </span>
        <Badge
          tone={isAuction ? 'info' : 'primary'}
          className="absolute right-3 top-3 backdrop-blur"
        >
          {isAuction ? 'Auction' : 'Buy now'}
        </Badge>
      </div>

      <CardContent className="space-y-3">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate font-display text-lg font-semibold">
              {listing.domain_name}.str
            </p>
            <p className="text-xs text-muted-foreground">
              Listed {relativeTime(listing.created_at)}
            </p>
          </div>
          <Badge tone="neutral">{listing.domain_type}</Badge>
        </div>

        <div>
          <p className="text-xs uppercase tracking-wide text-muted-foreground">
            {isAuction ? 'Current bid' : 'Price'}
          </p>
          <p className="tabular text-xl font-semibold text-primary">
            {price(headline, listing.currency)}
          </p>
        </div>

        {listing.description && (
          <p className="line-clamp-2 text-sm text-muted-foreground">{listing.description}</p>
        )}

        {isAuction && listing.auction_end_at && (
          <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Timer className="size-3.5" aria-hidden="true" />
            Ends {shortDate(listing.auction_end_at)}
          </p>
        )}
      </CardContent>

      <div className="flex items-center gap-2 border-t border-border p-4">
        {isMine ? (
          <Badge tone="neutral">Your listing</Badge>
        ) : isAuction ? (
          <Button size="sm" variant="secondary" className="w-full" onClick={() => onBid(listing)}>
            <Gavel aria-hidden="true" />
            Place bid
          </Button>
        ) : (
          <Button size="sm" className="w-full" onClick={() => onReserve(listing)}>
            Reserve to buy
          </Button>
        )}
      </div>
    </Card>
  );
}

export default function Browse() {
  const userId = useUserId();
  const [tab, setTab] = useState<'domains' | 'tokens'>('domains');
  const [query, setQuery] = useState('');
  const [domainType, setDomainType] = useState('all');
  const [reserving, setReserving] = useState<DomainListing | null>(null);
  const [bidding, setBidding] = useState<DomainListing | null>(null);
  const [bidAmount, setBidAmount] = useState('');

  const stats = useMarketplaceStats();
  const domains = useDomainListings('active', domainType);
  const tokens = useTokenListings('active');
  const reserve = useReserveListing();
  const placeBid = usePlaceBid();

  const filteredDomains = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return domains.data ?? [];
    return (domains.data ?? []).filter((l) => l.domain_name.toLowerCase().includes(q));
  }, [domains.data, query]);

  const filteredTokens = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return tokens.data ?? [];
    return (tokens.data ?? []).filter((l) => l.asset_symbol.toLowerCase().includes(q));
  }, [tokens.data, query]);

  const closeReserve = () => {
    setReserving(null);
    reserve.reset();
  };

  const closeBid = () => {
    setBidding(null);
    setBidAmount('');
    placeBid.reset();
  };

  const submitReserve = () => {
    if (!reserving) return;
    reserve.mutate(
      { listing: reserving, hours: RESERVATION_HOURS },
      {
        onSuccess: () => {
          toast.success(
            `${reserving.domain_name}.str is held for you for ${RESERVATION_HOURS} hours. Pay the seller, then add your payment reference under Activity.`
          );
          closeReserve();
        },
      }
    );
  };

  const submitBid = () => {
    if (!bidding) return;
    placeBid.mutate(
      { listing: bidding, amount: Number(bidAmount) },
      {
        onSuccess: () => {
          toast.success('Bid placed. The seller will review it.');
          closeBid();
        },
      }
    );
  };

  return (
    <>
      <PageHeader
        title="Marketplace"
        description="STR domains and tokens listed by members of the network."
        actions={
          <>
            <Button asChild variant="secondary">
              <Link to="/marketplace/sell">
                <Store aria-hidden="true" />
                Sell
              </Link>
            </Button>
            <Button asChild variant="ghost">
              <Link to="/marketplace/activity">Activity</Link>
            </Button>
          </>
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Stat
          label="Domains listed"
          value={stats.data?.domainListings ?? '—'}
          icon={<Globe className="size-4" />}
          loading={stats.isPending}
        />
        <Stat
          label="Token offerings"
          value={stats.data?.tokenListings ?? '—'}
          icon={<Coins className="size-4" />}
          loading={stats.isPending}
        />
        <Stat
          label="Reservation window"
          value={`${RESERVATION_HOURS}h`}
          sub="How long a buy-now claim is held for payment"
        />
      </div>

      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <Tabs
          label="Marketplace category"
          value={tab}
          onChange={setTab}
          options={[
            { value: 'domains', label: 'Domains' },
            { value: 'tokens', label: 'Tokens' },
          ]}
        />
        <div className="relative w-full sm:w-64">
          <Search
            className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
            aria-hidden="true"
          />
          <Input
            className="pl-9"
            placeholder={tab === 'domains' ? 'Search domains' : 'Search tokens'}
            aria-label={tab === 'domains' ? 'Search domains' : 'Search tokens'}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
      </div>

      {tab === 'domains' && (
        <Section title="Domain listings">
          <div className="flex flex-wrap gap-2">
            {DOMAIN_TYPES.map((t) => (
              <Button
                key={t.value}
                size="sm"
                variant={domainType === t.value ? 'primary' : 'outline'}
                onClick={() => setDomainType(t.value)}
              >
                {t.label}
              </Button>
            ))}
          </div>

          {domains.isPending ? (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-52 w-full" />
              ))}
            </div>
          ) : domains.isError ? (
            <Card>
              <ErrorState error={domains.error} onRetry={() => void domains.refetch()} />
            </Card>
          ) : filteredDomains.length === 0 ? (
            <Card>
              <EmptyState
                icon={<Globe className="size-5" />}
                title="No domains listed here yet"
                description={
                  query
                    ? 'No listing matches that search. Try a different name or category.'
                    : 'Nothing is on sale in this category right now.'
                }
                action={
                  <Button asChild variant="secondary" size="sm">
                    <Link to="/marketplace/sell">List a domain</Link>
                  </Button>
                }
              />
            </Card>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {filteredDomains.map((listing) => (
                <DomainCard
                  key={listing.id}
                  listing={listing}
                  isMine={listing.seller_id === userId}
                  onReserve={setReserving}
                  onBid={(l) => {
                    setBidding(l);
                    setBidAmount('');
                  }}
                />
              ))}
            </div>
          )}
        </Section>
      )}

      {tab === 'tokens' && (
        <Section
          title="Token offerings"
          description="Amounts shown are held in marketplace escrow by the seller."
        >
          <Card>
            {tokens.isPending ? (
              <RowsSkeleton />
            ) : tokens.isError ? (
              <ErrorState error={tokens.error} onRetry={() => void tokens.refetch()} />
            ) : filteredTokens.length === 0 ? (
              <EmptyState
                icon={<Coins className="size-5" />}
                title="No token offerings"
                description="Nobody has tokens on sale right now."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Asset</TH>
                      <TH>Amount</TH>
                      <TH>Price per unit</TH>
                      <TH>Total</TH>
                      <TH>Type</TH>
                      <TH>Listed</TH>
                      <TH>Purchase</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {filteredTokens.map((listing) => (
                      <TR key={listing.id}>
                        <TD className="font-medium">{listing.asset_symbol}</TD>
                        <TD className="tabular">
                          {tokenAmount(listing.amount, listing.asset_symbol)}
                        </TD>
                        <TD className="tabular">{price(listing.price_per_unit, 'EUR')}</TD>
                        <TD className="tabular">{price(listing.total_price, 'EUR')}</TD>
                        <TD>
                          <Badge tone={listing.listing_type === 'buy_now' ? 'primary' : 'info'}>
                            {listing.listing_type === 'buy_now' ? 'Buy now' : 'Auction'}
                          </Badge>
                        </TD>
                        <TD className="text-muted-foreground">{relativeTime(listing.created_at)}</TD>
                        <TD>
                          {listing.seller_id === userId ? (
                            <Badge tone="neutral">Your listing</Badge>
                          ) : (
                            /*
                             * TODO(server): settling a token purchase has to move the
                             * buyer's fiat and release the seller's escrowed tokens in one
                             * transaction. `debit_fiat_wallet` covers only the buyer's leg
                             * and there is no RPC that credits the seller or releases
                             * `marketplace_escrow_balances`, so a client-side attempt would
                             * take the buyer's money and deliver nothing. Needs
                             * `settle_token_listing(p_listing_id, p_buyer_id)` — a
                             * service-role RPC that locks the escrow row, debits fiat,
                             * credits both pools and marks the listing sold — or an
                             * equivalent edge function.
                             */
                            <BlockedAction
                              label="Buy"
                              reason="Purchases are disabled until settlement runs on the server. Buying here would take payment without releasing the tokens."
                            />
                          )}
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Card>
        </Section>
      )}

      <Modal
        open={!!reserving}
        onClose={closeReserve}
        title={reserving ? `Reserve ${reserving.domain_name}.str` : 'Reserve'}
        description={`The listing is held for you for ${RESERVATION_HOURS} hours while you pay the seller directly.`}
      >
        {reserving && (
          <>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-muted-foreground">Price</dt>
                <dd className="tabular font-medium">
                  {price(reserving.buy_now_price, reserving.currency)}
                </dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-muted-foreground">Pay in</dt>
                <dd className="font-medium">{reserving.currency}</dd>
              </div>
              <div className="flex flex-col gap-1">
                <dt className="text-muted-foreground">Seller payout address</dt>
                <dd className="break-all font-mono text-xs">
                  {payoutAddress(reserving) ?? 'Not provided'}
                </dd>
              </div>
            </dl>

            <p className="rounded-md bg-warning/10 px-3 py-2 text-xs text-warning">
              Reserving does not move any funds. You pay the seller at the address above and then
              record your transaction reference under Activity; an operator releases the domain once
              payment is verified.
            </p>

            <FormError error={reserve.error} />

            {payoutAddress(reserving) ? (
              <div className="flex items-center gap-2">
                <Button onClick={submitReserve} disabled={reserve.isPending}>
                  {reserve.isPending ? 'Reserving…' : `Reserve for ${RESERVATION_HOURS} hours`}
                </Button>
                <Button variant="ghost" onClick={closeReserve}>
                  Cancel
                </Button>
              </div>
            ) : (
              /*
               * TODO(server): with no payout address on the listing there is nowhere
               * to send payment. v2 fell back to hardcoded ADMIN_BTC_WALLET /
               * ADMIN_ETH_WALLET constants (BuyNowDialog.tsx), silently redirecting
               * the buyer's money to an address the seller never agreed to. A
               * platform escrow address must come from the server, per listing.
               */
              <BlockedAction
                label="Reserve"
                reason="This seller has not published a payout address, so there is nowhere to send payment. Ask them to update the listing."
              />
            )}
          </>
        )}
      </Modal>

      <Modal
        open={!!bidding}
        onClose={closeBid}
        title={bidding ? `Bid on ${bidding.domain_name}.str` : 'Place bid'}
        description="Your bid is recorded for the seller to review. No funds are taken now."
      >
        {bidding && (
          <>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-muted-foreground">Current bid</dt>
                <dd className="tabular font-medium">
                  {price(bidding.current_bid ?? bidding.starting_bid, bidding.currency)}
                </dd>
              </div>
              {bidding.auction_end_at && (
                <div className="flex justify-between gap-4">
                  <dt className="text-muted-foreground">Auction ends</dt>
                  <dd className="font-medium">{shortDate(bidding.auction_end_at)}</dd>
                </div>
              )}
            </dl>

            <Field
              label={`Your bid (${bidding.currency})`}
              htmlFor="bid-amount"
              hint="Must be higher than the current bid."
            >
              <Input
                id="bid-amount"
                type="number"
                min={0}
                step="any"
                inputMode="decimal"
                value={bidAmount}
                onChange={(e) => setBidAmount(e.target.value)}
              />
            </Field>

            <FormError error={placeBid.error} />

            <div className="flex items-center gap-2">
              <Button onClick={submitBid} disabled={placeBid.isPending || !bidAmount}>
                {placeBid.isPending ? 'Placing…' : 'Place bid'}
              </Button>
              <Button variant="ghost" onClick={closeBid}>
                Cancel
              </Button>
            </div>
          </>
        )}
      </Modal>
    </>
  );
}
