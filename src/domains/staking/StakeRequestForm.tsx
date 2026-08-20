import { useId, useMemo, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { token as formatToken, percent } from '@/lib/format';
import type { TokenPosition } from '@/lib/balances';
import { Select } from './components';
import {
  POOL_TYPES,
  POOL_TYPE_LABELS,
  TX_HASH_PATTERN,
  allowsInternalPayment,
  lockPeriodsFor,
  type LockPeriod,
  type PoolType,
} from './constants';
import { useApyQuote, usePoolTemplates, useSubmitStakingRequest } from './hooks';

/**
 * Open a staking position.
 *
 * The form never writes anything itself. It collects the request and hands it
 * to the `submit-staking-request` edge function, which re-validates every field
 * server-side under the caller's own identity and records a *pending* request.
 * No balance moves until an administrator approves it, and the rate that is
 * finally applied is set by the database at that point - the figure quoted here
 * comes from `calculate_dynamic_apy` and is labelled as an estimate.
 */

type PaymentMethod = 'external' | 'internal';

interface Errors {
  amount?: string;
  transactionHash?: string;
  domainName?: string;
  strDomainUsername?: string;
  fullName?: string;
  strDomainOwned?: string;
}

export function StakeRequestForm({ positions }: { positions: TokenPosition[] }) {
  const ids = useId();
  const [poolType, setPoolType] = useState<PoolType>('str');
  const [lockPeriod, setLockPeriod] = useState<LockPeriod>('12');
  const [amount, setAmount] = useState('');
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('external');
  const [transactionHash, setTransactionHash] = useState('');
  const [domainName, setDomainName] = useState('');
  const [strDomainUsername, setStrDomainUsername] = useState('');
  const [fullName, setFullName] = useState('');
  const [strDomainOwned, setStrDomainOwned] = useState('');
  const [description, setDescription] = useState('');
  const [errors, setErrors] = useState<Errors>({});

  const templates = usePoolTemplates(true);
  const submit = useSubmitStakingRequest();

  const months = Number(lockPeriod);
  const numericAmount = Number(amount);
  const quote = useApyQuote(numericAmount, months);

  const periods = lockPeriodsFor(poolType);
  const isDomain = poolType === 'domain';
  const canPayInternally = allowsInternalPayment(poolType);
  const effectivePayment: PaymentMethod = canPayInternally ? paymentMethod : 'external';
  const needsHash = !isDomain && effectivePayment === 'external';

  /** The advertised range for this token and term, straight from the pool row. */
  const template = useMemo(
    () =>
      (templates.data ?? []).find(
        (t) => t.token_type?.toLowerCase() === poolType && t.duration_months === months
      ) ?? null,
    [templates.data, poolType, months]
  );

  const liquid = positions.find((p) => p.token === poolType)?.liquid ?? 0;

  function changePoolType(next: PoolType) {
    setPoolType(next);
    setErrors({});
    // Domain stakes have no 3-month term, and only CCOS may be paid internally.
    if (!lockPeriodsFor(next).includes(lockPeriod)) setLockPeriod('12');
    if (!allowsInternalPayment(next)) setPaymentMethod('external');
  }

  function validate(): Errors {
    const next: Errors = {};

    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      next.amount = 'Enter an amount greater than zero.';
    } else if (template?.min_stake_amount != null && numericAmount < template.min_stake_amount) {
      next.amount = `This pool has a ${formatToken(template.min_stake_amount, poolType)} minimum.`;
    } else if (template?.max_stake_amount != null && numericAmount > template.max_stake_amount) {
      next.amount = `This pool accepts at most ${formatToken(template.max_stake_amount, poolType)}.`;
    } else if (effectivePayment === 'internal' && numericAmount > liquid) {
      next.amount = `You hold ${formatToken(liquid, poolType)} in your wallet.`;
    }

    if (needsHash && !TX_HASH_PATTERN.test(transactionHash.trim())) {
      next.transactionHash = 'Enter the 0x-prefixed 64-character transfer hash.';
    }

    if (isDomain) {
      if (!domainName.trim()) next.domainName = 'Required for a domain stake.';
      if (!strDomainUsername.trim()) next.strDomainUsername = 'Required for a domain stake.';
      if (!fullName.trim()) next.fullName = 'Required for a domain stake.';
      if (!strDomainOwned.trim()) next.strDomainOwned = 'Required for a domain stake.';
    }

    return next;
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    const found = validate();
    setErrors(found);
    if (Object.keys(found).length > 0) return;

    submit.mutate(
      {
        poolType,
        requestType: 'stake',
        amount: numericAmount,
        lockPeriod,
        description,
        paymentMethod: effectivePayment,
        transactionHash: needsHash ? transactionHash : null,
        domainName: isDomain ? domainName : null,
        strDomainUsername: isDomain ? strDomainUsername : null,
        fullName: isDomain ? fullName : null,
        strDomainOwned: isDomain ? strDomainOwned : null,
      },
      {
        onSuccess: () => {
          toast.success('Request submitted', {
            description: 'An administrator will review it before the position opens.',
          });
          setAmount('');
          setTransactionHash('');
          setDescription('');
        },
        onError: (error: Error) => toast.error('Could not submit the request', {
          description: error.message,
        }),
      }
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4 p-5">
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Token" htmlFor={`${ids}-pool`}>
          <Select
            id={`${ids}-pool`}
            value={poolType}
            onChange={(e) => changePoolType(e.target.value as PoolType)}
          >
            {POOL_TYPES.map((t) => (
              <option key={t} value={t}>
                {POOL_TYPE_LABELS[t]}
              </option>
            ))}
          </Select>
        </Field>

        <Field
          label="Lock period"
          htmlFor={`${ids}-period`}
          hint={
            template
              ? `${template.name}: ${percent(template.apr_min)} – ${percent(template.apr_max)} advertised`
              : 'No published pool matches this term yet.'
          }
        >
          <Select
            id={`${ids}-period`}
            value={lockPeriod}
            onChange={(e) => setLockPeriod(e.target.value as LockPeriod)}
          >
            {periods.map((p) => (
              <option key={p} value={p}>
                {p} months
              </option>
            ))}
          </Select>
        </Field>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Amount"
          htmlFor={`${ids}-amount`}
          error={errors.amount}
          hint={`Wallet balance ${formatToken(liquid, poolType)}`}
        >
          <Input
            id={`${ids}-amount`}
            inputMode="decimal"
            type="number"
            min="0"
            step="any"
            value={amount}
            aria-invalid={!!errors.amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
          />
        </Field>

        <Field
          label="Estimated rate"
          hint="Quoted by the database. The rate applied at approval is authoritative."
        >
          <div className="flex h-9 items-center gap-2">
            {quote.isFetching ? (
              <span className="text-sm text-muted-foreground">Calculating…</span>
            ) : quote.isError ? (
              <span className="text-sm text-danger">Rate unavailable</span>
            ) : quote.data != null ? (
              <Badge tone="primary">{percent(quote.data)} APY</Badge>
            ) : (
              <span className="text-sm text-muted-foreground">Enter an amount</span>
            )}
          </div>
        </Field>
      </div>

      {canPayInternally && (
        <Field
          label="Funding"
          htmlFor={`${ids}-payment`}
          hint="Internal funding is checked against your wallet balance server-side."
        >
          <Select
            id={`${ids}-payment`}
            value={paymentMethod}
            onChange={(e) => setPaymentMethod(e.target.value as PaymentMethod)}
          >
            <option value="external">External wallet transfer</option>
            <option value="internal">Internal wallet balance</option>
          </Select>
        </Field>
      )}

      {needsHash && (
        <Field
          label="Transfer hash"
          htmlFor={`${ids}-hash`}
          error={errors.transactionHash}
          hint="The on-chain transaction that funded this stake."
        >
          <Input
            id={`${ids}-hash`}
            value={transactionHash}
            aria-invalid={!!errors.transactionHash}
            onChange={(e) => setTransactionHash(e.target.value)}
            placeholder="0x…"
          />
        </Field>
      )}

      {isDomain && (
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Domain name" htmlFor={`${ids}-domain`} error={errors.domainName}>
            <Input
              id={`${ids}-domain`}
              value={domainName}
              aria-invalid={!!errors.domainName}
              onChange={(e) => setDomainName(e.target.value)}
            />
          </Field>
          <Field label="STR username" htmlFor={`${ids}-username`} error={errors.strDomainUsername}>
            <Input
              id={`${ids}-username`}
              value={strDomainUsername}
              aria-invalid={!!errors.strDomainUsername}
              onChange={(e) => setStrDomainUsername(e.target.value)}
              placeholder="str.example"
            />
          </Field>
          <Field label="Full name" htmlFor={`${ids}-fullname`} error={errors.fullName}>
            <Input
              id={`${ids}-fullname`}
              value={fullName}
              aria-invalid={!!errors.fullName}
              onChange={(e) => setFullName(e.target.value)}
            />
          </Field>
          <Field label="Domain owned" htmlFor={`${ids}-owned`} error={errors.strDomainOwned}>
            <Input
              id={`${ids}-owned`}
              value={strDomainOwned}
              aria-invalid={!!errors.strDomainOwned}
              onChange={(e) => setStrDomainOwned(e.target.value)}
            />
          </Field>
        </div>
      )}

      <Field label="Note (optional)" htmlFor={`${ids}-note`}>
        <Input
          id={`${ids}-note`}
          value={description}
          maxLength={500}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Anything the reviewer should know"
        />
      </Field>

      <div className="flex flex-wrap items-center gap-3 border-t border-border pt-4">
        <Button type="submit" disabled={submit.isPending}>
          {submit.isPending && <Loader2 className="animate-spin" />}
          Submit stake request
        </Button>
        <p className="text-xs text-muted-foreground">
          Requests are reviewed before any position opens. Nothing is debited by this form.
        </p>
      </div>
    </form>
  );
}
