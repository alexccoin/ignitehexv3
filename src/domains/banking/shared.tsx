import type { ReactNode, SelectHTMLAttributes } from 'react';
import { Link } from 'react-router-dom';
import { Landmark, Lock } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { StatusBadge } from '@/components/ui/status';
import { cn } from '@/lib/utils';

/**
 * Pieces shared by the banking routes.
 *
 * The point of AsyncSection is that loading, error and empty stop being
 * optional. In v2 each banking screen wrote its own `if (loading)` and then
 * rendered an unexplained blank box for both "no rows" and "the request
 * failed" — the two states a member most needs told apart.
 */

interface QueryLike<T> {
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  data: T | undefined;
  refetch: () => unknown;
}

export function AsyncSection<T>({
  query,
  emptyTitle,
  emptyDescription,
  emptyAction,
  skeletonClassName = 'h-32 w-full',
  children,
}: {
  query: QueryLike<T>;
  emptyTitle: string;
  emptyDescription?: string;
  emptyAction?: ReactNode;
  skeletonClassName?: string;
  children: (data: T) => ReactNode;
}) {
  if (query.isLoading) return <Skeleton className={skeletonClassName} />;
  if (query.isError) return <ErrorState error={query.error} onRetry={() => query.refetch()} />;

  const data = query.data;
  if (data === undefined || data === null) {
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  }
  if (Array.isArray(data) && data.length === 0) {
    return <EmptyState title={emptyTitle} description={emptyDescription} action={emptyAction} />;
  }

  return <>{children(data)}</>;
}

/**
 * A native select wearing the Input treatment.
 *
 * The design system has no listbox yet, and a native select is the correct
 * control for a short, known list — it is keyboard- and screen-reader-complete
 * without any of the roving-tabindex work a custom one would need.
 */
export function SelectInput({
  className,
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        'flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm transition-colors',
        'disabled:cursor-not-allowed disabled:opacity-50',
        className
      )}
      {...props}
    >
      {children}
    </select>
  );
}

/** A labelled figure inside a panel, for rows of secondary numbers. */
export function Metric({
  label,
  value,
  hint,
  className,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('rounded-lg border border-border p-3', className)}>
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="tabular mt-1 text-lg font-semibold">{value}</p>
      {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

/**
 * Shown on every member screen until an application has been approved.
 *
 * RLS is what actually keeps an unapproved member out of the banking tables;
 * this only stops the UI from presenting a bank that does not exist yet.
 */
export function ApprovalGate({ status }: { status: string | null | undefined }) {
  const applied = !!status;

  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2">
            <Landmark className="size-5 text-primary" />
            CCoin Bank is not open on this account yet
          </CardTitle>
          <CardDescription>
            {applied
              ? 'Your application has been received. IBANs, cards and settlement unlock once it is approved.'
              : 'Apply once to open EUR, CHF and GBP accounts, a CCoin network card and on-chain settlement.'}
          </CardDescription>
        </div>
        {applied && <StatusBadge status={status} />}
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-3">
          {[
            ['Multi-currency IBANs', 'EUR, CHF and GBP accounts under one identity.'],
            ['CCoin network card', 'Issued against an STR domain you already hold.'],
            ['On-chain settlement', 'Every movement written to the CCoin ledger.'],
          ].map(([title, body]) => (
            <div key={title} className="rounded-lg border border-border p-3">
              <p className="text-sm font-medium">{title}</p>
              <p className="mt-1 text-xs text-muted-foreground">{body}</p>
            </div>
          ))}
        </div>

        {!applied && (
          <Button asChild>
            <Link to="/banking/apply">Start an application</Link>
          </Button>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * An action with no server-side path yet.
 *
 * Rendering it disabled and saying why is the honest option. v2's alternative
 * was to wire the button straight to a table update, which is how balances
 * ended up mutable from the browser.
 */
export function ServerActionPending({
  label,
  todo,
  className,
}: {
  label: string;
  todo: string;
  className?: string;
}) {
  return (
    <div className={cn('rounded-lg border border-dashed border-border p-3', className)}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Lock className="size-4 text-muted-foreground" />
          <span className="text-sm font-medium">{label}</span>
        </div>
        <Button size="sm" variant="secondary" disabled>
          Unavailable
        </Button>
      </div>
      <p className="mt-2 text-xs text-muted-foreground">
        <Badge tone="warning" className="mr-2 align-middle">
          TODO
        </Badge>
        {todo}
      </p>
    </div>
  );
}
