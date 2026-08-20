import type { ReactNode } from 'react';
import { Info, Lock, ShieldAlert } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { cn } from '@/lib/utils';

/**
 * Pieces shared by the identity routes.
 *
 * `AsyncSection` and `ServerActionPending` are deliberate copies of the two in
 * `domains/banking/shared.tsx`. Importing across domains would give this module
 * a dependency on the banking domain it has no business holding; the right
 * resolution is to promote both into `components/ui` now that a second domain
 * needs them, which is a change to shared code and therefore not something this
 * feature makes on its own. Named here so the next person does not have to
 * rediscover it.
 */

interface QueryLike<T> {
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  data: T | undefined;
  refetch: () => unknown;
}

/** Loading, error and empty as three separate answers, never one blank box. */
export function AsyncSection<T>({
  query,
  emptyTitle,
  emptyDescription,
  emptyAction,
  emptyIcon,
  skeletonClassName = 'h-32 w-full',
  children,
}: {
  query: QueryLike<T>;
  emptyTitle: string;
  emptyDescription?: string;
  emptyAction?: ReactNode;
  emptyIcon?: ReactNode;
  skeletonClassName?: string;
  children: (data: T) => ReactNode;
}) {
  if (query.isLoading) return <Skeleton className={skeletonClassName} />;
  if (query.isError) return <ErrorState error={query.error} onRetry={() => query.refetch()} />;

  const data = query.data;
  if (data === undefined || data === null || (Array.isArray(data) && data.length === 0)) {
    return (
      <EmptyState
        title={emptyTitle}
        description={emptyDescription}
        action={emptyAction}
        icon={emptyIcon}
      />
    );
  }

  return <>{children(data)}</>;
}

/**
 * An action with no server-side path yet.
 *
 * Rendering it disabled and saying exactly what is missing is the honest
 * option. v2's alternative was to wire the button straight to a table update,
 * which is how a "Connected" pill came to mean nothing at all.
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

/** A quiet, non-alarming note. Used for statements about what the page knows. */
export function Note({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <p className={cn('flex items-start gap-2 text-xs text-muted-foreground', className)}>
      <Info className="mt-0.5 size-3.5 shrink-0" />
      <span>{children}</span>
    </p>
  );
}

/**
 * Shown beside a status this deployment cannot stand behind.
 *
 * This is the whole point of the feature. A `connected` row on a property with
 * nothing behind it is a claim the platform cannot support, and the page says
 * so next to the badge rather than quietly rendering a green pill — which is
 * precisely what v2's WalletModal did.
 */
export function UnverifiableStatus({ property }: { property: string }) {
  return (
    <p className="flex items-start gap-2 rounded-lg bg-warning/10 p-3 text-xs text-warning ring-1 ring-inset ring-warning/20">
      <ShieldAlert className="mt-0.5 size-3.5 shrink-0" />
      <span>
        This link is recorded as connected, but nothing on this deployment can check it against{' '}
        {property}. Treat the status as a record someone entered, not as a live confirmation.
      </span>
    </p>
  );
}
