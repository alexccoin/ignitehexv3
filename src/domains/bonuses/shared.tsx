import { useState, type ReactNode } from 'react';
import { Check, Copy, Lock, ShieldAlert, ShieldCheck } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { money, token as tokenAmount } from '@/lib/format';
import { cn } from '@/lib/utils';
import { SAFE_MODE_RELEASE_PHRASE, useSafeMode } from './safeMode';

/**
 * The pieces the four bonus screens share: one way to render the states a
 * query can be in, one way to present an action the browser is not allowed to
 * perform, and the safe-mode gate that stands in front of every credit.
 */

/** A titled panel, so section headings stay identical across the domain. */
export function Section({
  title,
  description,
  actions,
  children,
  bodyClassName,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
  bodyClassName?: string;
}) {
  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle>{title}</CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </div>
        {actions}
      </CardHeader>
      <CardContent className={cn('pt-4', bodyClassName)}>{children}</CardContent>
    </Card>
  );
}

interface AsyncProps<T> {
  query: {
    isLoading: boolean;
    isError: boolean;
    error: unknown;
    data: T | undefined;
    refetch: () => unknown;
  };
  /** True when the query succeeded but there is nothing to show. */
  isEmpty?: (data: T) => boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  emptyAction?: ReactNode;
  skeleton?: ReactNode;
  children: (data: T) => ReactNode;
}

/**
 * Loading, error, empty and loaded, in that order, every time.
 *
 * "Nothing here yet" and "we could not load this" are different messages. v2's
 * referral screen conflated them: a failed query and a member with no referrals
 * both rendered the same empty table, so a broken policy looked like a quiet
 * month.
 */
export function Async<T>({
  query,
  isEmpty,
  emptyTitle = 'Nothing yet',
  emptyDescription,
  emptyAction,
  skeleton,
  children,
}: AsyncProps<T>) {
  if (query.isLoading) return <>{skeleton ?? <Skeleton className="h-32 w-full" />}</>;
  if (query.isError) return <ErrorState error={query.error} onRetry={() => void query.refetch()} />;
  if (query.data === undefined)
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  if (isEmpty?.(query.data))
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  return <>{children(query.data)}</>;
}

/**
 * An action that exists in the product but not in the browser.
 *
 * Anything that moves value has to happen in one server-side statement. Where
 * v3 has no such endpoint, the control is rendered disabled with the reason
 * beside it rather than quietly omitted, so the gap stays visible instead of
 * being rediscovered by someone reimplementing v2's read-modify-write.
 */
export function LockedAction({
  label,
  reason,
  className,
}: {
  label: string;
  reason: string;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-wrap items-center gap-3', className)}>
      <Button variant="secondary" size="sm" disabled>
        <Lock aria-hidden="true" />
        {label}
      </Button>
      <p className="flex-1 text-xs text-muted-foreground">{reason}</p>
    </div>
  );
}

/** A short label/value pair for detail panels. */
export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="space-y-0.5">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="tabular text-sm font-medium">{value}</p>
    </div>
  );
}

/** A row of filter or selector pills. */
export function Pills({
  options,
  value,
  onChange,
  label,
  render,
}: {
  options: readonly string[];
  value: string;
  onChange: (next: string) => void;
  label: string;
  render?: (option: string) => string;
}) {
  return (
    <div className="flex flex-wrap gap-2" role="group" aria-label={label}>
      {options.map((option) => (
        <button
          key={option}
          type="button"
          aria-pressed={value === option}
          onClick={() => onChange(option)}
          className={cn(
            'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
            value === option
              ? 'bg-primary/10 text-primary ring-primary/20'
              : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
          )}
        >
          {render ? render(option) : option.replace(/_/g, ' ')}
        </button>
      ))}
    </div>
  );
}

/**
 * Format a reward amount.
 *
 * `null` renders as an em dash rather than as zero: a pending voucher has no
 * agreed value, and showing "0 STR" would read as "you were given nothing"
 * rather than "this has not been valued yet".
 */
export function amountLabel(symbol: string, amount: number | null): string {
  if (amount === null) return '—';
  if (symbol === 'usd') return money(amount, 'USD');
  return tokenAmount(amount, symbol);
}

/** A read-only value with a copy button. Used for referral links. */
export function CopyField({ value, label }: { value: string; label: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <div className="flex gap-2">
      <Input value={value} readOnly aria-label={label} className="font-mono text-xs" />
      <Button
        variant="secondary"
        size="icon"
        aria-label={copied ? `${label} copied` : `Copy ${label}`}
        onClick={() => {
          void navigator.clipboard.writeText(value).then(() => {
            setCopied(true);
            window.setTimeout(() => setCopied(false), 2000);
          });
        }}
      >
        {copied ? <Check aria-hidden="true" /> : <Copy aria-hidden="true" />}
      </Button>
    </div>
  );
}

/**
 * The safe-mode gate.
 *
 * Every crediting path in the admin screen sits behind this. It is engaged by
 * default, it re-engages fifteen minutes after release, and releasing it means
 * typing the phrase out in full — there is no toggle, because a toggle is one
 * mis-click away from a live payout run.
 */
export function SafeModeGate() {
  const { blocked, secondsRemaining, release, engage } = useSafeMode();
  const [phrase, setPhrase] = useState('');
  const [failed, setFailed] = useState(false);

  const minutes = Math.floor(secondsRemaining / 60);
  const seconds = secondsRemaining % 60;

  return (
    <Card className={cn('border-l-4', blocked ? 'border-l-warning' : 'border-l-danger')}>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2">
            {blocked ? (
              <ShieldCheck className="size-4 text-warning" aria-hidden="true" />
            ) : (
              <ShieldAlert className="size-4 text-danger" aria-hidden="true" />
            )}
            Safe mode
          </CardTitle>
          <CardDescription>
            {blocked
              ? 'Crediting is blocked. Review, correction lookups and dry runs are available; nothing can be pushed to a member balance.'
              : 'Crediting is open. Every approval and sweep you run from here will move tokens.'}
          </CardDescription>
        </div>
        <Badge tone={blocked ? 'warning' : 'danger'}>
          {blocked ? 'Blocked' : `Open — ${minutes}:${String(seconds).padStart(2, '0')} left`}
        </Badge>
      </CardHeader>
      <CardContent className="pt-4">
        {blocked ? (
          <form
            className="flex flex-wrap items-start gap-3"
            onSubmit={(e) => {
              e.preventDefault();
              const ok = release(phrase);
              setFailed(!ok);
              if (ok) setPhrase('');
            }}
          >
            <div className="min-w-56 flex-1 space-y-1.5">
              <Input
                value={phrase}
                onChange={(e) => {
                  setPhrase(e.target.value);
                  setFailed(false);
                }}
                aria-label={`Type ${SAFE_MODE_RELEASE_PHRASE} to release safe mode`}
                aria-invalid={failed}
                placeholder={SAFE_MODE_RELEASE_PHRASE}
                className="font-mono"
              />
              <p className={cn('text-xs', failed ? 'text-danger' : 'text-muted-foreground')}>
                {failed
                  ? `That is not the phrase. Type ${SAFE_MODE_RELEASE_PHRASE} exactly, in capitals.`
                  : `Type ${SAFE_MODE_RELEASE_PHRASE} to open a 15 minute crediting window.`}
              </p>
            </div>
            <Button type="submit" variant="danger" disabled={phrase.trim().length === 0}>
              Release
            </Button>
          </form>
        ) : (
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="secondary" onClick={engage}>
              <Lock aria-hidden="true" />
              Re-engage now
            </Button>
            <p className="flex-1 text-xs text-muted-foreground">
              Safe mode re-engages on its own when the window runs out, and again when you leave this
              screen.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
