import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Coins, Globe, ShieldCheck } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Field, Input, Label } from '@/components/ui/input';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Table, TableWrap, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { useStakingPools } from '@/hooks/data';
import { relativeTime, token as tokenAmount } from '@/lib/format';
import {
  EscrowInconsistencyError,
  useCancelDomainListing,
  useCreateDomainListing,
  useCreateTokenListing,
  useDomainListings,
  useMyDomains,
  useMyEscrow,
  useTokenListings,
  type StrDomain,
} from './hooks';
import { BlockedAction, FormError, RowsSkeleton, Section, Tabs, price } from './shared';

const DOMAIN_CURRENCIES = ['EUR', 'USD', 'BTC', 'ETH'];

/* ------------------------------------------------------------- sell tokens */

function SellTokens() {
  const pools = useStakingPools();
  const escrow = useMyEscrow();
  const myListings = useTokenListings('mine');
  const create = useCreateTokenListing();

  const [symbol, setSymbol] = useState('');
  const [amount, setAmount] = useState('');
  const [listingType, setListingType] = useState<'buy_now' | 'auction'>('buy_now');
  const [pricePerUnit, setPricePerUnit] = useState('');
  const [startingBid, setStartingBid] = useState('');
  const [reservePrice, setReservePrice] = useState('');
  const [auctionDays, setAuctionDays] = useState('7');
  const [description, setDescription] = useState('');

  const positions = pools.data?.positions ?? [];
  const selected = positions.find((p) => p.token === symbol.toLowerCase());
  const numericAmount = Number(amount);

  // Liquid balance only. Staked and reward balances are not spendable, and v2's
  // wallet conflated the three.
  const liquid = selected?.liquid ?? 0;
  const overBalance = numericAmount > liquid;

  const total = useMemo(() => {
    const unit = Number(pricePerUnit);
    if (!Number.isFinite(unit) || !Number.isFinite(numericAmount)) return null;
    return unit * numericAmount;
  }, [pricePerUnit, numericAmount]);

  const canSubmit =
    !!symbol &&
    Number.isFinite(numericAmount) &&
    numericAmount > 0 &&
    !overBalance &&
    (listingType === 'buy_now' ? !!pricePerUnit : !!startingBid) &&
    !create.isPending;

  const submit = () => {
    create.mutate(
      {
        symbol,
        amount: numericAmount,
        listingType,
        pricePerUnit: listingType === 'buy_now' && pricePerUnit ? Number(pricePerUnit) : null,
        startingBid: listingType === 'auction' && startingBid ? Number(startingBid) : null,
        reservePrice: reservePrice ? Number(reservePrice) : null,
        auctionDays: listingType === 'auction' ? Number(auctionDays) : null,
        description: description.trim() || null,
      },
      {
        onSuccess: () => {
          toast.success(
            `${numericAmount} ${symbol.toUpperCase()} moved into escrow and listed for sale.`
          );
          setAmount('');
          setPricePerUnit('');
          setStartingBid('');
          setReservePrice('');
          setDescription('');
        },
        onError: (err) => {
          // A debit that succeeded without its escrow record is not an ordinary
          // validation failure and must not disappear into a red toast.
          if (err instanceof EscrowInconsistencyError) {
            toast.error(err.message, { duration: Number.POSITIVE_INFINITY, closeButton: true });
          }
        },
      }
    );
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>List tokens for sale</CardTitle>
            <CardDescription>
              The amount you list is debited from your liquid pool balance and held in escrow until
              the listing sells or is released.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="flex items-start gap-2 rounded-md bg-info/10 px-3 py-2 text-xs text-info">
            <ShieldCheck className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
            <span>
              The debit runs inside a single server-side transaction that locks your pool row and
              refuses to overdraw it. Nothing about your balance is calculated in this browser.
            </span>
          </p>

          {pools.isError ? (
            <ErrorState error={pools.error} onRetry={() => void pools.refetch()} />
          ) : (
            <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field
                  label="Token"
                  htmlFor="sell-token"
                  hint={
                    pools.isPending
                      ? 'Loading your balances…'
                      : selected
                        ? `${tokenAmount(liquid, selected.token)} available`
                        : 'Choose a token you hold.'
                  }
                >
                  <select
                    id="sell-token"
                    className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                    value={symbol}
                    onChange={(e) => setSymbol(e.target.value)}
                  >
                    <option value="">Select a token</option>
                    {positions
                      .filter((p) => p.liquid > 0)
                      .map((p) => (
                        <option key={p.token} value={p.token}>
                          {p.token.toUpperCase()} — {tokenAmount(p.liquid, p.token)} available
                        </option>
                      ))}
                  </select>
                </Field>

                <Field
                  label="Amount"
                  htmlFor="sell-amount"
                  error={overBalance ? 'That is more than your available balance.' : undefined}
                  hint={!overBalance ? 'How many tokens to move into escrow.' : undefined}
                >
                  <Input
                    id="sell-amount"
                    type="number"
                    min={0}
                    step="any"
                    inputMode="decimal"
                    aria-invalid={overBalance}
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                  />
                </Field>
              </div>

              <div className="space-y-1.5">
                <Label>Sale type</Label>
                <Tabs
                  label="Sale type"
                  value={listingType}
                  onChange={setListingType}
                  options={[
                    { value: 'buy_now', label: 'Fixed price' },
                    { value: 'auction', label: 'Auction' },
                  ]}
                />
              </div>

              {listingType === 'buy_now' ? (
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field
                    label="Price per token (EUR)"
                    htmlFor="sell-unit"
                    hint={total !== null && total > 0 ? `Total ${price(total, 'EUR')}` : undefined}
                  >
                    <Input
                      id="sell-unit"
                      type="number"
                      min={0}
                      step="any"
                      inputMode="decimal"
                      value={pricePerUnit}
                      onChange={(e) => setPricePerUnit(e.target.value)}
                    />
                  </Field>
                </div>
              ) : (
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field label="Starting bid (EUR)" htmlFor="sell-start">
                    <Input
                      id="sell-start"
                      type="number"
                      min={0}
                      step="any"
                      inputMode="decimal"
                      value={startingBid}
                      onChange={(e) => setStartingBid(e.target.value)}
                    />
                  </Field>
                  <Field label="Reserve price (EUR)" htmlFor="sell-reserve" hint="Optional.">
                    <Input
                      id="sell-reserve"
                      type="number"
                      min={0}
                      step="any"
                      inputMode="decimal"
                      value={reservePrice}
                      onChange={(e) => setReservePrice(e.target.value)}
                    />
                  </Field>
                  <Field label="Runs for (days)" htmlFor="sell-days">
                    <Input
                      id="sell-days"
                      type="number"
                      min={1}
                      max={30}
                      value={auctionDays}
                      onChange={(e) => setAuctionDays(e.target.value)}
                    />
                  </Field>
                </div>
              )}

              <Field label="Description" htmlFor="sell-desc" hint="Optional.">
                <Input
                  id="sell-desc"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
              </Field>

              <FormError error={create.error} />

              <Button onClick={submit} disabled={!canSubmit}>
                {create.isPending ? 'Locking tokens…' : 'Lock tokens and list'}
              </Button>
            </>
          )}
        </CardContent>
      </Card>

      <Section title="Your token listings">
        <Card>
          {myListings.isPending ? (
            <RowsSkeleton />
          ) : myListings.isError ? (
            <ErrorState error={myListings.error} onRetry={() => void myListings.refetch()} />
          ) : (myListings.data ?? []).length === 0 ? (
            <EmptyState
              icon={<Coins className="size-5" />}
              title="No token listings"
              description="Tokens you list for sale appear here with the amount held in escrow."
            />
          ) : (
            <>
              {/* The escrow column is a separate query; if it failed, say so
                  rather than rendering an empty cell that reads as "nothing
                  locked". */}
              {escrow.isError && (
                <p role="alert" className="px-4 pt-4 text-sm text-warning">
                  Escrow holdings could not be loaded, so the escrow column below is incomplete.
                </p>
              )}
              <TableWrap>
                <Table>
                <THead>
                  <TR>
                    <TH>Asset</TH>
                    <TH>Amount</TH>
                    <TH>Price</TH>
                    <TH>Status</TH>
                    <TH>Escrow</TH>
                    <TH>Listed</TH>
                    <TH>Actions</TH>
                  </TR>
                </THead>
                <TBody>
                  {(myListings.data ?? []).map((listing) => {
                    const held = (escrow.data ?? []).find(
                      (e) => e.listing_id === listing.id && e.status === 'locked'
                    );
                    return (
                      <TR key={listing.id}>
                        <TD className="font-medium">{listing.asset_symbol}</TD>
                        <TD className="tabular">
                          {tokenAmount(listing.amount, listing.asset_symbol)}
                        </TD>
                        <TD className="tabular">
                          {price(listing.total_price ?? listing.starting_bid, 'EUR')}
                        </TD>
                        <TD>
                          <StatusBadge status={listing.status} />
                        </TD>
                        <TD>
                          {held ? (
                            <Badge tone="warning">
                              {tokenAmount(held.amount, held.asset_symbol)} locked
                            </Badge>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TD>
                        <TD className="text-muted-foreground">{relativeTime(listing.created_at)}</TD>
                        <TD>
                          {/*
                           * TODO(server): cancelling has to return the escrowed tokens.
                           * Migration 20260509121934 revoked user UPDATE on
                           * user_staking_pools and shipped only `debit_staking_pool_balance`
                           * — there is no credit counterpart, so nothing here can put the
                           * tokens back. v2 did the read-modify-write anyway
                           * (UnifiedMarketplaceListings.tsx:180-197): RLS dropped the update,
                           * the escrow row was still marked released, and the tokens vanished
                           * from both places. Needs
                           * `release_marketplace_escrow(p_listing_id)` — a service-role RPC
                           * that credits the pool and closes the escrow row atomically.
                           */}
                          <BlockedAction
                            label="Cancel listing"
                            reason="Cancelling is disabled: there is no server function to return escrowed tokens, and doing it from the browser would release the escrow without crediting your balance."
                          />
                        </TD>
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
              </TableWrap>
            </>
          )}
        </Card>
      </Section>
    </div>
  );
}

/* ------------------------------------------------------------ sell domains */

function SellDomains() {
  const domains = useMyDomains();
  const myListings = useDomainListings('mine');
  const create = useCreateDomainListing();
  const cancel = useCancelDomainListing();

  const [domainId, setDomainId] = useState('');
  const [listingType, setListingType] = useState<'buy_now' | 'auction'>('buy_now');
  const [currency, setCurrency] = useState('EUR');
  const [buyNowPrice, setBuyNowPrice] = useState('');
  const [startingBid, setStartingBid] = useState('');
  const [reservePrice, setReservePrice] = useState('');
  const [auctionDays, setAuctionDays] = useState('7');
  const [description, setDescription] = useState('');
  const [payoutAddress, setPayoutAddress] = useState('');

  const listedIds = new Set(
    (myListings.data ?? [])
      .filter((l) => l.status === 'active' || l.status === 'reserved')
      .map((l) => l.domain_id)
  );

  const sellable: StrDomain[] = (domains.data ?? []).filter(
    (d) => d.status === 'minted' && !listedIds.has(d.id)
  );
  const selected = sellable.find((d) => d.id === domainId) ?? null;

  // Required for every currency: a listing with no payout address gives the
  // buyer nowhere to pay, which is the gap v2 filled with a hardcoded admin
  // wallet constant.
  const isCrypto = currency === 'BTC' || currency === 'ETH';
  const canSubmit =
    !!selected &&
    (listingType === 'buy_now' ? !!buyNowPrice : !!startingBid) &&
    payoutAddress.trim().length > 8 &&
    !create.isPending;

  const submit = () => {
    if (!selected) return;
    create.mutate(
      {
        domainId: selected.id,
        domainName: selected.domain_name,
        domainType: selected.domain_type,
        listingType,
        currency,
        buyNowPrice: listingType === 'buy_now' && buyNowPrice ? Number(buyNowPrice) : null,
        startingBid: listingType === 'auction' && startingBid ? Number(startingBid) : null,
        reservePrice: reservePrice ? Number(reservePrice) : null,
        auctionDays: listingType === 'auction' ? Number(auctionDays) : null,
        description: description.trim() || null,
        payoutAddress: payoutAddress.trim() || null,
      },
      {
        onSuccess: () => {
          toast.success(`${selected.domain_name}.str is now listed.`);
          setDomainId('');
          setBuyNowPrice('');
          setStartingBid('');
          setReservePrice('');
          setDescription('');
          setPayoutAddress('');
        },
      }
    );
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>List a domain</CardTitle>
            <CardDescription>
              Listing a domain does not transfer it. Ownership moves only once an operator verifies
              the buyer's payment.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {domains.isPending ? (
            <RowsSkeleton rows={3} />
          ) : domains.isError ? (
            <ErrorState error={domains.error} onRetry={() => void domains.refetch()} />
          ) : sellable.length === 0 ? (
            <EmptyState
              icon={<Globe className="size-5" />}
              title="No domains available to list"
              description="Only minted domains that are not already listed can be sold."
              action={
                <Button asChild variant="secondary" size="sm">
                  <Link to="/marketplace/domains">Manage your domains</Link>
                </Button>
              }
            />
          ) : (
            <>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Domain" htmlFor="listing-domain">
                  <select
                    id="listing-domain"
                    className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                    value={domainId}
                    onChange={(e) => setDomainId(e.target.value)}
                  >
                    <option value="">Select a domain</option>
                    {sellable.map((d) => (
                      <option key={d.id} value={d.id}>
                        {d.domain_name}.str ({d.domain_type})
                      </option>
                    ))}
                  </select>
                </Field>

                <Field label="Currency" htmlFor="listing-currency">
                  <select
                    id="listing-currency"
                    className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                    value={currency}
                    onChange={(e) => setCurrency(e.target.value)}
                  >
                    {DOMAIN_CURRENCIES.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>
                </Field>
              </div>

              <div className="space-y-1.5">
                <Label>Sale type</Label>
                <Tabs
                  label="Domain sale type"
                  value={listingType}
                  onChange={setListingType}
                  options={[
                    { value: 'buy_now', label: 'Buy now' },
                    { value: 'auction', label: 'Auction' },
                  ]}
                />
              </div>

              {listingType === 'buy_now' ? (
                <Field label={`Price (${currency})`} htmlFor="listing-price">
                  <Input
                    id="listing-price"
                    type="number"
                    min={0}
                    step="any"
                    inputMode="decimal"
                    value={buyNowPrice}
                    onChange={(e) => setBuyNowPrice(e.target.value)}
                  />
                </Field>
              ) : (
                <div className="grid gap-4 sm:grid-cols-3">
                  <Field label={`Starting bid (${currency})`} htmlFor="listing-start">
                    <Input
                      id="listing-start"
                      type="number"
                      min={0}
                      step="any"
                      inputMode="decimal"
                      value={startingBid}
                      onChange={(e) => setStartingBid(e.target.value)}
                    />
                  </Field>
                  <Field label={`Reserve (${currency})`} htmlFor="listing-reserve" hint="Optional.">
                    <Input
                      id="listing-reserve"
                      type="number"
                      min={0}
                      step="any"
                      inputMode="decimal"
                      value={reservePrice}
                      onChange={(e) => setReservePrice(e.target.value)}
                    />
                  </Field>
                  <Field label="Runs for (days)" htmlFor="listing-days">
                    <Input
                      id="listing-days"
                      type="number"
                      min={1}
                      max={30}
                      value={auctionDays}
                      onChange={(e) => setAuctionDays(e.target.value)}
                    />
                  </Field>
                </div>
              )}

              <Field
                label={isCrypto ? `${currency} payout address` : 'Payout account (IBAN)'}
                htmlFor="listing-payout"
                hint={`Buyers pay you here directly in ${currency}. Nothing is filled in on your behalf, and a listing without one cannot be reserved.`}
              >
                <Input
                  id="listing-payout"
                  value={payoutAddress}
                  onChange={(e) => setPayoutAddress(e.target.value)}
                  placeholder={isCrypto ? `Your ${currency} address` : 'Your IBAN'}
                />
              </Field>

              <Field label="Description" htmlFor="listing-desc" hint="Optional.">
                <Input
                  id="listing-desc"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                />
              </Field>

              <FormError error={create.error} />

              <Button onClick={submit} disabled={!canSubmit}>
                {create.isPending ? 'Listing…' : 'List domain'}
              </Button>
            </>
          )}
        </CardContent>
      </Card>

      <Section title="Your domain listings">
        <Card>
          {myListings.isPending ? (
            <RowsSkeleton />
          ) : myListings.isError ? (
            <ErrorState error={myListings.error} onRetry={() => void myListings.refetch()} />
          ) : (myListings.data ?? []).length === 0 ? (
            <EmptyState
              icon={<Globe className="size-5" />}
              title="No domain listings"
              description="Domains you put up for sale appear here."
            />
          ) : (
            <>
              <FormError error={cancel.error} />
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Domain</TH>
                      <TH>Type</TH>
                      <TH>Price</TH>
                      <TH>Status</TH>
                      <TH>Listed</TH>
                      <TH>Actions</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {(myListings.data ?? []).map((listing) => (
                      <TR key={listing.id}>
                        <TD className="font-medium">{listing.domain_name}.str</TD>
                        <TD>
                          <Badge tone={listing.listing_type === 'buy_now' ? 'primary' : 'info'}>
                            {listing.listing_type === 'buy_now' ? 'Buy now' : 'Auction'}
                          </Badge>
                        </TD>
                        <TD className="tabular">
                          {price(
                            listing.buy_now_price ?? listing.current_bid ?? listing.starting_bid,
                            listing.currency
                          )}
                        </TD>
                        <TD>
                          <StatusBadge status={listing.status} />
                        </TD>
                        <TD className="text-muted-foreground">{relativeTime(listing.created_at)}</TD>
                        <TD>
                          {listing.status === 'active' ? (
                            <Button
                              variant="secondary"
                              size="sm"
                              disabled={cancel.isPending}
                              onClick={() =>
                                cancel.mutate(listing.id, {
                                  onSuccess: () => toast.success('Listing withdrawn.'),
                                })
                              }
                            >
                              Withdraw
                            </Button>
                          ) : listing.status === 'reserved' ? (
                            <span className="text-xs text-muted-foreground">
                              Reserved by a buyer
                            </span>
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
    </div>
  );
}

/* -------------------------------------------------------------------- page */

export default function Sell() {
  const [tab, setTab] = useState<'tokens' | 'domains'>('tokens');

  return (
    <>
      <PageHeader
        title="Sell"
        description="Put tokens or an STR domain on the marketplace."
        actions={
          <Button asChild variant="ghost">
            <Link to="/marketplace">Back to listings</Link>
          </Button>
        }
      />

      <div className="mb-5">
        <Tabs
          label="What to sell"
          value={tab}
          onChange={setTab}
          options={[
            { value: 'tokens', label: 'Tokens' },
            { value: 'domains', label: 'Domains' },
          ]}
        />
      </div>

      {tab === 'tokens' ? <SellTokens /> : <SellDomains />}
    </>
  );
}
