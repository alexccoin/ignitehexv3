import { useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import { Building2, Landmark, Package, Trash2 } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Field, Input, Label } from '@/components/ui/input';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Table, TableWrap, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { maskIban, money, shortDate } from '@/lib/format';
import {
  useApplyForMerchantAccount,
  useCreateProduct,
  useDeleteProduct,
  useMerchant,
  useMerchantEligibility,
  useMerchantProducts,
  useSetProductActive,
  type MerchantAccount,
} from './hooks';
import { BlockedAction, FormError, Modal, RowsSkeleton, Section } from './shared';

const PRODUCT_CURRENCIES = ['EUR', 'USD', 'CHF', 'GBP'];
const PRODUCT_CATEGORIES = [
  'Digital goods',
  'Physical goods',
  'Services',
  'Subscriptions',
  'Consulting',
  'Software',
  'Other',
];

/* ----------------------------------------------------------- application */

function ApplicationForm() {
  const eligibility = useMerchantEligibility();
  const apply = useApplyForMerchantAccount();

  const [businessDomainId, setBusinessDomainId] = useState('');
  const [businessDescription, setBusinessDescription] = useState('');
  const [productsServices, setProductsServices] = useState('');
  const [monthlyVolume, setMonthlyVolume] = useState('');
  const [averageTransaction, setAverageTransaction] = useState('');
  const [wantsIban, setWantsIban] = useState(true);
  const [wantsProcessing, setWantsProcessing] = useState(true);

  if (eligibility.isPending) return <RowsSkeleton rows={4} />;
  if (eligibility.isError) {
    return <ErrorState error={eligibility.error} onRetry={() => void eligibility.refetch()} />;
  }

  const { personalBankingId, businessDomains } = eligibility.data;
  const selectedDomain = businessDomains.find((d) => d.id === businessDomainId) ?? null;

  // Both foreign keys are NOT NULL, so the form is only offered when both
  // prerequisites exist rather than failing at insert time.
  if (!personalBankingId || businessDomains.length === 0) {
    return (
      <EmptyState
        icon={<Building2 className="size-5" />}
        title="Not eligible yet"
        description={
          !personalBankingId
            ? 'A merchant account is built on an approved personal banking application. Yours is not approved yet.'
            : 'You need an active business domain before you can apply. Mint one first.'
        }
        action={
          businessDomains.length === 0 ? (
            <Button asChild variant="secondary" size="sm">
              <Link to="/marketplace/domains">Manage domains</Link>
            </Button>
          ) : undefined
        }
      />
    );
  }

  const submit = () => {
    if (!selectedDomain) return;
    apply.mutate(
      {
        businessName: selectedDomain.business_name,
        businessDomainId: selectedDomain.id,
        personalBankingId,
        businessDescription: businessDescription.trim() || null,
        productsServices: productsServices.trim() || null,
        expectedMonthlyVolume: monthlyVolume.trim() || null,
        averageTransactionSize: averageTransaction.trim() || null,
        wantsMultiCurrencyIban: wantsIban,
        wantsPaymentProcessing: wantsProcessing,
      },
      { onSuccess: () => toast.success('Merchant application submitted for review.') }
    );
  };

  return (
    <div className="space-y-4">
      <Field label="Business domain" htmlFor="merchant-domain">
        <select
          id="merchant-domain"
          className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
          value={businessDomainId}
          onChange={(e) => setBusinessDomainId(e.target.value)}
        >
          <option value="">Select a business domain</option>
          {businessDomains.map((d) => (
            <option key={d.id} value={d.id}>
              {d.domain_name}.str — {d.business_name}
            </option>
          ))}
        </select>
      </Field>

      <Field label="What the business does" htmlFor="merchant-desc">
        <Input
          id="merchant-desc"
          value={businessDescription}
          onChange={(e) => setBusinessDescription(e.target.value)}
        />
      </Field>

      <Field label="Products and services" htmlFor="merchant-products">
        <Input
          id="merchant-products"
          value={productsServices}
          onChange={(e) => setProductsServices(e.target.value)}
        />
      </Field>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Expected monthly volume" htmlFor="merchant-volume" hint="Optional.">
          <Input
            id="merchant-volume"
            value={monthlyVolume}
            onChange={(e) => setMonthlyVolume(e.target.value)}
          />
        </Field>
        <Field label="Average transaction size" htmlFor="merchant-avg" hint="Optional.">
          <Input
            id="merchant-avg"
            value={averageTransaction}
            onChange={(e) => setAverageTransaction(e.target.value)}
          />
        </Field>
      </div>

      <fieldset className="space-y-2">
        <legend className="text-sm font-medium">Products requested</legend>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={wantsIban}
            onChange={(e) => setWantsIban(e.target.checked)}
          />
          Multi-currency business IBANs
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={wantsProcessing}
            onChange={(e) => setWantsProcessing(e.target.checked)}
          />
          Payment processing
        </label>
      </fieldset>

      <FormError error={apply.error} />

      <Button onClick={submit} disabled={!selectedDomain || apply.isPending}>
        {apply.isPending ? 'Submitting…' : 'Submit application'}
      </Button>
    </div>
  );
}

/* -------------------------------------------------------------- products */

function Products({ account }: { account: MerchantAccount }) {
  const products = useMerchantProducts(account.id);
  const create = useCreateProduct();
  const setActive = useSetProductActive();
  const remove = useDeleteProduct();

  const [open, setOpen] = useState(false);
  const [productName, setProductName] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState(PRODUCT_CATEGORIES[0]);
  const [priceValue, setPriceValue] = useState('');
  const [currency, setCurrency] = useState('EUR');
  const [stock, setStock] = useState('');
  const [isDigital, setIsDigital] = useState(false);

  const rows = products.data ?? [];

  const submit = () => {
    create.mutate(
      {
        merchantRowId: account.id,
        productName,
        description: description.trim() || null,
        category,
        price: Number(priceValue),
        priceCurrency: currency,
        stockQuantity: stock ? Number(stock) : null,
        isDigital,
      },
      {
        onSuccess: () => {
          toast.success(`${productName.trim()} added to your catalogue.`);
          setOpen(false);
          setProductName('');
          setDescription('');
          setPriceValue('');
          setStock('');
        },
      }
    );
  };

  return (
    <Section
      title="Catalogue"
      description="Prices are stored in the currency you enter. No conversion is invented here."
      actions={
        <Button size="sm" onClick={() => setOpen(true)}>
          Add product
        </Button>
      }
    >
      <Card>
        {products.isPending ? (
          <RowsSkeleton />
        ) : products.isError ? (
          <ErrorState error={products.error} onRetry={() => void products.refetch()} />
        ) : rows.length === 0 ? (
          <EmptyState
            icon={<Package className="size-5" />}
            title="No products yet"
            description="Add what your business sells so it can be listed."
            action={
              <Button size="sm" variant="secondary" onClick={() => setOpen(true)}>
                Add product
              </Button>
            }
          />
        ) : (
          <>
            <FormError error={setActive.error ?? remove.error} />
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Product</TH>
                    <TH>Category</TH>
                    <TH>Price</TH>
                    <TH>Stock</TH>
                    <TH>State</TH>
                    <TH>Added</TH>
                    <TH>Actions</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((product) => (
                    <TR key={product.id}>
                      <TD>
                        <div className="space-y-0.5">
                          <p className="font-medium">{product.product_name}</p>
                          {product.description && (
                            <p className="line-clamp-1 text-xs text-muted-foreground">
                              {product.description}
                            </p>
                          )}
                        </div>
                      </TD>
                      <TD className="text-muted-foreground">{product.category ?? '—'}</TD>
                      <TD className="tabular">{money(product.price, product.price_currency)}</TD>
                      <TD className="tabular">
                        {product.is_digital ? 'Digital' : (product.stock_quantity ?? '—')}
                      </TD>
                      <TD>
                        <Badge tone={product.is_active ? 'success' : 'neutral'}>
                          {product.is_active ? 'Active' : 'Hidden'}
                        </Badge>
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(product.created_at)}</TD>
                      <TD>
                        <div className="flex items-center gap-1">
                          <Button
                            variant="ghost"
                            size="sm"
                            disabled={setActive.isPending}
                            onClick={() =>
                              setActive.mutate(
                                { productId: product.id, isActive: !product.is_active },
                                {
                                  onSuccess: () =>
                                    toast.success(
                                      product.is_active ? 'Product hidden.' : 'Product published.'
                                    ),
                                }
                              )
                            }
                          >
                            {product.is_active ? 'Hide' : 'Publish'}
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label={`Delete ${product.product_name}`}
                            disabled={remove.isPending}
                            onClick={() =>
                              remove.mutate(product.id, {
                                onSuccess: () => toast.success('Product deleted.'),
                              })
                            }
                          >
                            <Trash2 />
                          </Button>
                        </div>
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          </>
        )}
      </Card>

      <Modal open={open} onClose={() => setOpen(false)} title="Add product">
        <Field label="Name" htmlFor="product-name">
          <Input
            id="product-name"
            value={productName}
            onChange={(e) => setProductName(e.target.value)}
          />
        </Field>
        <Field label="Description" htmlFor="product-desc" hint="Optional.">
          <Input
            id="product-desc"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Price" htmlFor="product-price">
            <Input
              id="product-price"
              type="number"
              min={0}
              step="0.01"
              inputMode="decimal"
              value={priceValue}
              onChange={(e) => setPriceValue(e.target.value)}
            />
          </Field>
          <Field label="Currency" htmlFor="product-currency">
            <select
              id="product-currency"
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
            >
              {PRODUCT_CURRENCIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Category" htmlFor="product-category">
            <select
              id="product-category"
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
            >
              {PRODUCT_CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Stock" htmlFor="product-stock" hint="Leave blank for digital goods.">
            <Input
              id="product-stock"
              type="number"
              min={0}
              value={stock}
              disabled={isDigital}
              onChange={(e) => setStock(e.target.value)}
            />
          </Field>
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={isDigital}
            onChange={(e) => setIsDigital(e.target.checked)}
          />
          Digital product
        </label>

        <p className="rounded-md bg-info/10 px-3 py-2 text-xs text-info">
          Crypto pricing is not offered here. v2 stored hardcoded &ldquo;simulated&rdquo; exchange
          rates on every row and then summed them as real revenue; a live rate has to come from the
          server.
        </p>

        <FormError error={create.error} />

        <div className="flex items-center gap-2">
          <Button onClick={submit} disabled={!productName.trim() || !priceValue || create.isPending}>
            {create.isPending ? 'Saving…' : 'Add product'}
          </Button>
          <Button variant="ghost" onClick={() => setOpen(false)}>
            Cancel
          </Button>
        </div>
      </Modal>
    </Section>
  );
}

/* ------------------------------------------------------------------ page */

export default function Merchant() {
  const merchant = useMerchant();

  if (merchant.isPending) {
    return (
      <>
        <PageHeader title="Merchant" description="Accept payments as a business on the network." />
        <Card>
          <RowsSkeleton rows={5} />
        </Card>
      </>
    );
  }

  if (merchant.isError) {
    return (
      <>
        <PageHeader title="Merchant" description="Accept payments as a business on the network." />
        <Card>
          <ErrorState error={merchant.error} onRetry={() => void merchant.refetch()} />
        </Card>
      </>
    );
  }

  const { account, application, ibans } = merchant.data;

  if (!account) {
    return (
      <>
        <PageHeader
          title="Merchant"
          description="Accept payments as a business on the network."
          actions={application ? <StatusBadge status={application.status} /> : undefined}
        />
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>
                {application ? 'Your application' : 'Apply for a merchant account'}
              </CardTitle>
              <CardDescription>
                {application
                  ? 'An operator is reviewing your application. You will get business IBANs and a catalogue once it is approved.'
                  : 'Merchant accounts come with business IBANs and a product catalogue.'}
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent>
            {application ? (
              <dl className="grid gap-3 text-sm sm:grid-cols-2">
                <div>
                  <dt className="text-muted-foreground">Business</dt>
                  <dd className="font-medium">{application.business_name}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Submitted</dt>
                  <dd className="font-medium">{shortDate(application.created_at)}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Status</dt>
                  <dd>
                    <StatusBadge status={application.status} />
                  </dd>
                </div>
                {application.admin_notes && (
                  <div className="sm:col-span-2">
                    <dt className="text-muted-foreground">Reviewer notes</dt>
                    <dd>{application.admin_notes}</dd>
                  </div>
                )}
              </dl>
            ) : (
              <ApplicationForm />
            )}
          </CardContent>
        </Card>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title={account.business_name}
        description={`Merchant ${account.merchant_id}`}
        actions={<StatusBadge status={account.status} />}
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Stat
          label="Business IBANs"
          value={ibans.length}
          icon={<Landmark className="size-4" />}
          sub="Balances are maintained by the banking ledger"
        />
        <Stat
          label="Payment processing"
          value={account.payment_processing_enabled ? 'Enabled' : 'Off'}
          tone={account.payment_processing_enabled ? 'success' : 'default'}
        />
        <Stat label="Opened" value={shortDate(account.created_at)} />
      </div>

      <div className="space-y-8">
        <Products account={account} />

        <Section
          title="Business IBANs"
          description="Read-only. Balances come from the banking ledger and are never written here."
        >
          <Card>
            {ibans.length === 0 ? (
              <EmptyState
                icon={<Landmark className="size-5" />}
                title="No business IBANs"
                description="Your account has no business IBANs provisioned yet."
                action={
                  /*
                   * TODO(server): issuing a business IBAN must generate a valid,
                   * unique account number and open it at zero on the ledger. v2
                   * built one in the browser out of Math.random() with uncomputed
                   * check digits (MerchantBusinessIBANs.tsx:43-46) and inserted the
                   * `balance` column directly, so a client could set its own opening
                   * balance. Needs `issue_merchant_iban(p_merchant_id, p_currency)`
                   * or an edge function that mints and registers the account.
                   */
                  <BlockedAction
                    label="Request IBAN"
                    reason="IBANs must be issued and registered by the banking service. Generating one in the browser would produce an invalid account with a self-declared balance."
                  />
                }
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Currency</TH>
                      <TH>IBAN</TH>
                      <TH>BIC</TH>
                      <TH>Holder</TH>
                      <TH>Balance</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {ibans.map((iban) => (
                      <TR key={iban.id}>
                        <TD className="font-medium">{iban.currency}</TD>
                        <TD className="font-mono text-xs">
                          {iban.is_encrypted ? 'Encrypted' : maskIban(iban.iban)}
                        </TD>
                        <TD className="font-mono text-xs">
                          {iban.is_encrypted ? 'Encrypted' : iban.bic}
                        </TD>
                        <TD className="text-muted-foreground">{iban.account_holder}</TD>
                        <TD className="tabular">{money(iban.balance, iban.currency)}</TD>
                        <TD>
                          <StatusBadge status={iban.status} />
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Card>
        </Section>

        <Section
          title="Taking payments"
          description="Everything that moves money needs a server-side path that does not exist yet."
        >
          <Card>
            <CardContent className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {/*
               * TODO(server): a point-of-sale charge debits the payer and credits the
               * merchant IBAN in one transaction. `debit_fiat_wallet` covers only the
               * payer's leg — there is no credit counterpart — so a client-side
               * implementation would take the customer's money and never deliver it.
               * v2's POS avoided the problem by never settling at all: it wrote a
               * pending row priced with hardcoded "simulated" exchange rates
               * (MerchantPOS.tsx:38-44) that the dashboard then summed as revenue.
               * Needs `settle_pos_charge(p_reference_id)`.
               */}
              <div className="space-y-2">
                <Label>Point of sale</Label>
                <BlockedAction
                  label="Take a payment"
                  reason="Charging a customer needs one server-side transaction that debits the payer and credits your IBAN. No such function exists, and the exchange rate must come from a live source."
                />
              </div>

              {/*
               * TODO(server): a business transfer debits one IBAN and credits another.
               * `debit_fiat_wallet(p_user_id, p_currency, p_amount)` handles the debit
               * with a row lock but nothing credits the beneficiary, so a failure after
               * the debit loses the money outright. Needs
               * `transfer_between_ibans(p_from_iban_id, p_to_iban, p_amount)`.
               */}
              <div className="space-y-2">
                <Label>Send money</Label>
                <BlockedAction
                  label="Send from IBAN"
                  reason="Outbound transfers are disabled: the debit and the credit have to happen together on the server, and only the debit half exists."
                />
              </div>

              {/*
               * TODO(server): marking an invoice paid is a settlement, not a status
               * change. Doing it client-side lets a merchant mark their own invoice
               * paid without any money moving. Needs
               * `settle_invoice(p_invoice_id, p_payment_reference)`.
               */}
              <div className="space-y-2">
                <Label>Invoicing</Label>
                <BlockedAction
                  label="Mark invoice paid"
                  reason="Settling an invoice has to be recorded against a real payment on the server, not toggled from the browser."
                />
              </div>
            </CardContent>
          </Card>
        </Section>
      </div>
    </>
  );
}
