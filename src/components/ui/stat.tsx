import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';
import { Skeleton } from './skeleton';

/** A single headline figure. The value uses tabular figures so a row of these
 *  reads as a set rather than as unrelated numbers. */
export function Stat({
  label,
  value,
  sub,
  icon,
  tone = 'default',
  loading,
  className,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  icon?: ReactNode;
  tone?: 'default' | 'primary' | 'success' | 'warning' | 'danger';
  loading?: boolean;
  className?: string;
}) {
  const toneClass = {
    default: 'text-foreground',
    primary: 'text-primary',
    success: 'text-success',
    warning: 'text-warning',
    danger: 'text-danger',
  }[tone];

  return (
    <div className={cn('panel p-5', className)}>
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
        {icon && <span className="text-muted-foreground">{icon}</span>}
      </div>
      {loading ? (
        <Skeleton className="mt-3 h-8 w-28" />
      ) : (
        <p className={cn('tabular mt-2 text-2xl font-semibold', toneClass)}>{value}</p>
      )}
      {sub && !loading && <p className="mt-1 text-xs text-muted-foreground">{sub}</p>}
    </div>
  );
}
