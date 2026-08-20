import { useMemo, useState, type SelectHTMLAttributes } from 'react';
import { toast } from 'sonner';
import { ArrowLeftRight, Check, Copy, Download, Loader2, Send } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { useStakingPools } from '@/hooks/data';
import { token as fmtToken, money } from '@/lib/format';
import { cn } from '@/lib/utils';
import {
  EXTERNAL_RAILS,
  WALLET_TOKENS,
  useAvailableBalances,
  useFiatTransfer,
  useFiatWallets,
  useReceiveAddresses,
  useSendTokens,
  useSwap,
  type FiatTransferType,
} from './hooks';

/** Native select styled to match Input, so forms do not need a popover library. */
function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        'flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm text-foreground transition-colors',
        'disabled:cursor-not-allowed disabled:opacity-50',
        className
      )}
      {...props}
    />
  );
}

const FIAT_TRANSFER_TYPES: { value: FiatTransferType; label: string }[] = [
  { value: 'network', label: 'Network · str.domain' },
  { value: 'account', label: 'Account · IBAN' },
  { value: 'email', label: 'Email address' },
  { value: 'sepa', label: 'SEPA' },
  { value: 'uk_payment', label: 'UK Faster Payments' },
  { value: 'wire', label: 'Wire' },
  { value: 'swift', label: 'SWIFT' },
];

/**
 * Everything that moves value out of the wallet.
 *
 * Each of the three forms hands the whole operation to a server-side function.
 * Nothing on this page reads a balance, subtracts from it and writes it back —
 * the browser proposes, the server decides.
 */
export default function WalletTransfers() {
  return (
    <>
      <PageHeader
        title="Transfers"
        description="Send tokens, convert between assets and move cash off the platform."
      />
      <div className="grid gap-6 lg:grid-cols-2">
        <SendTokensCard />
        <ReceiveCard />
        <ConvertCard />
        <FiatTransferCard />
      </div>
    </>
  );
}

/* ------------------------------------------------------------------- send */

function SendTokensCard() {
  const pools = useStakingPools();
  const available = useAvailableBalances();
  const send = useSendTokens();

  const tokens = useMemo(() => {
    const seen = new Set<string>(WALLET_TOKENS);
    for (const p of pools.data?.positions ?? []) seen.add(p.token);
    return [...seen].sort();
  }, [pools.data]);

  const [tokenType, setTokenType] = useState<string>('str');
  const [toAddress, setToAddress] = useState('');
  const [amount, setAmount] = useState('');
  const [pin, setPin] = useState('');

  const spendable = available.data?.[tokenType];
  // `undefined` = not asked, `null` = asked and the server did not answer.
  const spendableKnown = typeof spendable === 'number';
  const amountNum = Number(amount);

  const addressError =
    toAddress && !(toAddress.startsWith('str.') || toAddress.length >= 26)
      ? 'Enter a str.domain (str.name) or a full STR wallet address.'
      : undefined;

  const amountError =
    amount && (!Number.isFinite(amountNum) || amountNum <= 0)
      ? 'Enter an amount greater than zero.'
      : spendableKnown && amountNum > spendable
        ? `More than you can spend. Available ${fmtToken(spendable, tokenType)}.`
        : undefined;

  const blocked = !toAddress || !amount || !!addressError || !!amountError || !spendableKnown;

  const submit = () => {
    send.mutate(
      { toAddress: toAddress.trim(), amount: amountNum, tokenType, pin: pin || undefined },
      {
        onSuccess: (result) => {
          toast.success(result.message ?? `Sent ${fmtToken(amountNum, tokenType)} to ${toAddress}`);
          setToAddress('');
          setAmount('');
          setPin('');
        },
        onError: (error: Error) => toast.error(error.message),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Send tokens</CardTitle>
          <CardDescription>
            To a str.domain or a wallet address. Settled by the platform, not by this page.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-4 pt-3">
        <Field label="Token" htmlFor="send-token">
          <Select
            id="send-token"
            value={tokenType}
            onChange={(e) => setTokenType(e.target.value)}
            disabled={send.isPending}
          >
            {tokens.map((t) => (
              <option key={t} value={t}>
                {t.toUpperCase()}
              </option>
            ))}
          </Select>
        </Field>

        <p className="text-xs text-muted-foreground">
          {available.isLoading ? (
            <Skeleton as="span" className="h-3 w-32" />
          ) : spendableKnown ? (
            <>
              Available <span className="tabular">{fmtToken(spendable, tokenType)}</span>
            </>
          ) : (
            <span className="text-warning">
              Spendable balance unavailable — sending is disabled until it can be read.
            </span>
          )}
        </p>

        <Field label="Recipient" htmlFor="send-to" error={addressError} hint="str.john, or a full wallet address">
          <Input
            id="send-to"
            value={toAddress}
            onChange={(e) => setToAddress(e.target.value)}
            placeholder="str.john"
            aria-invalid={!!addressError}
            disabled={send.isPending}
          />
        </Field>

        <Field label="Amount" htmlFor="send-amount" error={amountError}>
          <div className="flex gap-2">
            <Input
              id="send-amount"
              type="number"
              step="0.0001"
              min="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              aria-invalid={!!amountError}
              disabled={send.isPending}
            />
            <Button
              type="button"
              variant="secondary"
              size="sm"
              className="shrink-0"
              disabled={!spendableKnown || send.isPending}
              onClick={() => spendableKnown && setAmount(String(spendable))}
            >
              Max
            </Button>
          </div>
        </Field>

        <Field label="Wallet PIN" htmlFor="send-pin" hint="Only required if you have set one.">
          <Input
            id="send-pin"
            type="password"
            inputMode="numeric"
            maxLength={6}
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            disabled={send.isPending}
          />
        </Field>

        <Button className="w-full" onClick={submit} disabled={blocked || send.isPending}>
          {send.isPending ? <Loader2 className="animate-spin" /> : <Send />}
          Send {tokenType.toUpperCase()}
        </Button>
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------------------- receive */

function CopyRow({ label, value }: { label: string; value: string }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error('Could not copy to the clipboard.');
    }
  };

  return (
    <div className="space-y-1.5">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="flex items-center gap-2">
        <code className="min-w-0 flex-1 truncate rounded-md border border-border bg-elevated px-3 py-2 font-mono text-sm">
          {value}
        </code>
        <Button
          variant="secondary"
          size="icon"
          className="shrink-0"
          onClick={() => void copy()}
          aria-label={copied ? `${label} copied` : `Copy ${label}`}
        >
          {copied ? <Check className="text-success" /> : <Copy />}
        </Button>
      </div>
    </div>
  );
}

function ReceiveCard() {
  const addresses = useReceiveAddresses();
  const strDomain = addresses.data?.strDomain;
  const walletAddress = addresses.data?.walletAddress;

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Receive</CardTitle>
          <CardDescription>Either identifier accepts a payment.</CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-4 pt-3">
        {addresses.isLoading ? (
          <>
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-16 w-full" />
          </>
        ) : addresses.isError ? (
          <ErrorState error={addresses.error} onRetry={() => void addresses.refetch()} />
        ) : !strDomain && !walletAddress ? (
          <EmptyState
            icon={<Download className="size-5" />}
            title="No addresses yet"
            description="Your str.domain and wallet address are issued when wallet setup completes."
          />
        ) : (
          <>
            {strDomain && <CopyRow label="STR domain" value={strDomain} />}
            {walletAddress && <CopyRow label="Wallet address" value={walletAddress} />}
          </>
        )}
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------------------- convert */

function ConvertCard() {
  const pools = useStakingPools();
  const available = useAvailableBalances();
  const swap = useSwap();

  const tokens = useMemo(() => {
    const seen = new Set<string>(WALLET_TOKENS);
    for (const p of pools.data?.positions ?? []) seen.add(p.token);
    return [...seen].sort();
  }, [pools.data]);

  const [fromToken, setFromToken] = useState('str');
  const [toToken, setToToken] = useState('wstr');
  const [amount, setAmount] = useState('');

  const spendable = available.data?.[fromToken];
  const spendableKnown = typeof spendable === 'number';
  const amountNum = Number(amount);

  const amountError =
    amount && (!Number.isFinite(amountNum) || amountNum <= 0)
      ? 'Enter an amount greater than zero.'
      : spendableKnown && amountNum > spendable
        ? `More than you can spend. Available ${fmtToken(spendable, fromToken)}.`
        : undefined;

  const flip = () => {
    setFromToken(toToken);
    setToToken(fromToken);
    setAmount('');
  };

  const submit = () => {
    swap.mutate(
      { fromToken: fromToken.toUpperCase(), toToken: toToken.toUpperCase(), fromAmount: amountNum },
      {
        onSuccess: (result) => {
          toast.success(
            `Converted ${fmtToken(result.from_amount, result.from_token)} to ${fmtToken(
              result.to_amount,
              result.to_token
            )}`
          );
          setAmount('');
        },
        onError: (error: Error) => toast.error(error.message),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Convert</CardTitle>
          <CardDescription>
            The rate is quoted and applied by the exchange when the conversion executes.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-4 pt-3">
        <div className="flex items-end gap-2">
          <Field label="From" htmlFor="swap-from">
            <Select
              id="swap-from"
              value={fromToken}
              onChange={(e) => setFromToken(e.target.value)}
              disabled={swap.isPending}
            >
              {tokens.map((t) => (
                <option key={t} value={t}>
                  {t.toUpperCase()}
                </option>
              ))}
            </Select>
          </Field>
          <Button
            variant="secondary"
            size="icon"
            className="mb-0.5 shrink-0"
            onClick={flip}
            aria-label="Swap the two assets around"
            disabled={swap.isPending}
          >
            <ArrowLeftRight />
          </Button>
          <Field label="To" htmlFor="swap-to">
            <Select
              id="swap-to"
              value={toToken}
              onChange={(e) => setToToken(e.target.value)}
              disabled={swap.isPending}
            >
              {tokens
                .filter((t) => t !== fromToken)
                .map((t) => (
                  <option key={t} value={t}>
                    {t.toUpperCase()}
                  </option>
                ))}
            </Select>
          </Field>
        </div>

        <p className="text-xs text-muted-foreground">
          {available.isLoading ? (
            <Skeleton as="span" className="h-3 w-32" />
          ) : spendableKnown ? (
            <>
              Available <span className="tabular">{fmtToken(spendable, fromToken)}</span>
            </>
          ) : (
            <span className="text-warning">
              Spendable balance unavailable — converting is disabled until it can be read.
            </span>
          )}
        </p>

        <Field label="Amount" htmlFor="swap-amount" error={amountError}>
          <Input
            id="swap-amount"
            type="number"
            step="0.0001"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            aria-invalid={!!amountError}
            disabled={swap.isPending}
          />
        </Field>

        <p className="rounded-lg border border-border bg-elevated p-3 text-xs text-muted-foreground">
          No estimate is shown here on purpose. v2 quoted the amount you would receive from a rate
          table hardcoded in the browser, which the exchange had never agreed to. The executed
          amount is confirmed once the conversion settles.
        </p>

        <Button
          className="w-full"
          onClick={submit}
          disabled={!amount || !!amountError || !spendableKnown || fromToken === toToken || swap.isPending}
        >
          {swap.isPending ? <Loader2 className="animate-spin" /> : <ArrowLeftRight />}
          Convert
        </Button>
      </CardContent>
    </Card>
  );
}

/* ----------------------------------------------------------- fiat transfer */

function FiatTransferCard() {
  const wallets = useFiatWallets();
  const transfer = useFiatTransfer();

  const [currency, setCurrency] = useState('EUR');
  const [transferType, setTransferType] = useState<FiatTransferType>('network');
  const [toIdentifier, setToIdentifier] = useState('');
  const [amount, setAmount] = useState('');
  const [reference, setReference] = useState('');
  const [recipientName, setRecipientName] = useState('');
  const [bankName, setBankName] = useState('');
  const [bankSwift, setBankSwift] = useState('');

  const wallet = (wallets.data ?? []).find((w) => w.currency === currency);
  const spendable = wallet ? Number(wallet.available_balance ?? 0) : null;
  const amountNum = Number(amount);
  const external = EXTERNAL_RAILS.includes(transferType);

  const amountError =
    amount && (!Number.isFinite(amountNum) || amountNum <= 0)
      ? 'Enter an amount greater than zero.'
      : spendable !== null && amountNum > spendable
        ? `More than the ${currency} wallet holds. Available ${money(spendable, currency)}.`
        : undefined;

  const missingBankDetails = external && (!recipientName.trim() || !bankName.trim());
  const missingSwift = (transferType === 'wire' || transferType === 'swift') && !bankSwift.trim();

  const submit = () => {
    transfer.mutate(
      {
        toIdentifier: toIdentifier.trim(),
        amount: amountNum,
        currency,
        transferType,
        reference: reference.trim() || undefined,
        recipientName: recipientName.trim() || undefined,
        recipientBankName: bankName.trim() || undefined,
        recipientBankSwift: bankSwift.trim() || undefined,
      },
      {
        onSuccess: (result) => {
          // A held transfer is a 200 with the money in the treasury. Saying
          // "sent" here would be a lie the member acts on.
          if (result.status === 'held') {
            toast.warning(
              result.message ??
                'The recipient could not be resolved. The funds are held in the treasury and can be refunded from Accounts.'
            );
          } else {
            toast.success(result.message ?? `Transfer of ${money(amountNum, currency)} submitted.`);
          }
          setToIdentifier('');
          setAmount('');
          setReference('');
        },
        onError: (error: Error) => toast.error(error.message),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Fiat transfer</CardTitle>
          <CardDescription>
            External rails carry a fee and need approval before they leave.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-4 pt-3">
        {wallets.isLoading ? (
          <Skeleton className="h-56 w-full" />
        ) : wallets.isError ? (
          <ErrorState error={wallets.error} onRetry={() => void wallets.refetch()} />
        ) : (wallets.data ?? []).length === 0 ? (
          <EmptyState
            title="No cash to send"
            description="A fiat wallet is opened the first time funds settle to you."
          />
        ) : (
          <>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Currency" htmlFor="fiat-currency">
                <Select
                  id="fiat-currency"
                  value={currency}
                  onChange={(e) => setCurrency(e.target.value)}
                  disabled={transfer.isPending}
                >
                  {(wallets.data ?? []).map((w) => (
                    <option key={w.id} value={w.currency}>
                      {w.currency}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Rail" htmlFor="fiat-rail">
                <Select
                  id="fiat-rail"
                  value={transferType}
                  onChange={(e) => setTransferType(e.target.value as FiatTransferType)}
                  disabled={transfer.isPending}
                >
                  {FIAT_TRANSFER_TYPES.map((t) => (
                    <option key={t.value} value={t.value}>
                      {t.label}
                    </option>
                  ))}
                </Select>
              </Field>
            </div>

            <p className="text-xs text-muted-foreground">
              {spendable === null ? (
                <span className="text-warning">You have no {currency} wallet.</span>
              ) : (
                <>
                  Available <span className="tabular">{money(spendable, currency)}</span>
                </>
              )}
            </p>

            <Field
              label="Recipient"
              htmlFor="fiat-to"
              hint={
                transferType === 'network'
                  ? 'A str.domain on the network'
                  : transferType === 'email'
                    ? 'The recipient’s email address'
                    : 'The destination IBAN'
              }
            >
              <Input
                id="fiat-to"
                value={toIdentifier}
                onChange={(e) => setToIdentifier(e.target.value)}
                disabled={transfer.isPending}
              />
            </Field>

            <Field label="Amount" htmlFor="fiat-amount" error={amountError}>
              <Input
                id="fiat-amount"
                type="number"
                step="0.01"
                min="0"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
                aria-invalid={!!amountError}
                disabled={transfer.isPending}
              />
            </Field>

            {external && (
              <div className="space-y-4 rounded-lg border border-border p-3">
                <p className="text-xs text-muted-foreground">
                  Required for transfers that leave the platform.
                </p>
                <Field label="Recipient name" htmlFor="fiat-name">
                  <Input
                    id="fiat-name"
                    value={recipientName}
                    onChange={(e) => setRecipientName(e.target.value)}
                    disabled={transfer.isPending}
                  />
                </Field>
                <Field label="Bank name" htmlFor="fiat-bank">
                  <Input
                    id="fiat-bank"
                    value={bankName}
                    onChange={(e) => setBankName(e.target.value)}
                    disabled={transfer.isPending}
                  />
                </Field>
                {(transferType === 'wire' || transferType === 'swift') && (
                  <Field label="SWIFT / BIC" htmlFor="fiat-swift">
                    <Input
                      id="fiat-swift"
                      value={bankSwift}
                      onChange={(e) => setBankSwift(e.target.value.toUpperCase())}
                      maxLength={11}
                      disabled={transfer.isPending}
                    />
                  </Field>
                )}
              </div>
            )}

            <Field label="Reference" htmlFor="fiat-ref" hint="Shown on the recipient’s statement.">
              <Input
                id="fiat-ref"
                value={reference}
                onChange={(e) => setReference(e.target.value)}
                maxLength={140}
                disabled={transfer.isPending}
              />
            </Field>

            <Button
              className="w-full"
              onClick={submit}
              disabled={
                !toIdentifier ||
                !amount ||
                !!amountError ||
                spendable === null ||
                missingBankDetails ||
                missingSwift ||
                transfer.isPending
              }
            >
              {transfer.isPending ? <Loader2 className="animate-spin" /> : <Send />}
              Send {currency}
            </Button>
          </>
        )}
      </CardContent>
    </Card>
  );
}
