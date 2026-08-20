import type { ReactNode } from 'react';
import { Lock } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { cn } from '@/lib/utils';

/**
 * Pieces shared by the investment screens.
 *
 * Chiefly two things: one way to render the four states a query can be in,
 * and one way to present an action the browser is not allowed to perform.
 */

/** A titled panel. Keeps section headings identical across the domain. */
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
 * "Nothing here yet" and "we could not load this" are different messages, and
 * v2 conflated them: a failed query rendered the same blank panel as a member
 * with no holdings, so a broken policy looked like an empty portfolio.
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
  if (query.isLoading) {
    return <>{skeleton ?? <Skeleton className="h-32 w-full" />}</>;
  }
  if (query.isError) {
    return <ErrorState error={query.error} onRetry={() => void query.refetch()} />;
  }
  if (query.data === undefined) {
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  }
  if (isEmpty?.(query.data)) {
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  }
  return <>{children(query.data)}</>;
}

/**
 * An action that exists in the product but not in the browser.
 *
 * Everything that moves money — crediting a voucher, settling a purchase,
 * depositing into a founder pool — has to happen in one server-side statement.
 * Where v3 has no such endpoint yet, the control is rendered disabled with the
 * reason next to it rather than quietly omitted, so the gap is visible instead
 * of being rediscovered later. The function each one needs is named in a TODO
 * at the call site.
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

/** A short label/value pair, used inside detail panels. */
export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="space-y-0.5">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="tabular text-sm font-medium">{value}</p>
    </div>
  );
}

/** A row of filter pills. */
export function FilterPills({
  options,
  value,
  onChange,
  label,
}: {
  options: readonly string[];
  value: string;
  onChange: (next: string) => void;
  label: string;
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
            'rounded-full px-3 py-1 text-xs font-medium capitalize ring-1 ring-inset transition-colors',
            value === option
              ? 'bg-primary/10 text-primary ring-primary/20'
              : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
          )}
        >
          {option.replace(/_/g, ' ')}
        </button>
      ))}
    </div>
  );
}
