import * as React from 'react';
import { cn } from '@/lib/utils';
import { percent, shortDate } from '@/lib/format';
import type { PoolRow } from './hooks';

/**
 * Small pieces shared by the four staking screens. Nothing in here decides a
 * number - it only renders values the database already supplied.
 */

/** Native select styled to match `Input`, so a picker is not a bespoke widget
 *  on every screen. */
export const Select = React.forwardRef<
  HTMLSelectElement,
  React.SelectHTMLAttributes<HTMLSelectElement>
>(({ className, ...props }, ref) => (
  <select
    ref={ref}
    className={cn(
      'flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm transition-colors',
      'disabled:cursor-not-allowed disabled:opacity-50',
      className
    )}
    {...props}
  />
));
Select.displayName = 'Select';

/** A row of mutually exclusive filters. */
export function Segmented<T extends string>({
  options,
  value,
  onChange,
  label,
}: {
  options: readonly { value: T; label: string }[];
  value: T;
  onChange: (next: T) => void;
  label: string;
}) {
  return (
    <div role="group" aria-label={label} className="inline-flex flex-wrap gap-1 rounded-lg bg-elevated p-1">
      {options.map((option) => {
        const active = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={active}
            onClick={() => onChange(option.value)}
            className={cn(
              'rounded-md px-3 py-1.5 text-xs font-medium transition-colors',
              active
                ? 'bg-surface text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground'
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

/**
 * The rate to display for an open position.
 *
 * `dynamic_apy` is the enhanced-pool override written at approval; `apy_rate`
 * is the fixed schedule. Both are database columns - the domain has no rate
 * table of its own.
 */
export function poolApy(pool: Pick<PoolRow, 'apy_rate' | 'dynamic_apy'>): number {
  const dynamic = Number(pool.dynamic_apy ?? Number.NaN);
  if (Number.isFinite(dynamic) && dynamic > 0) return dynamic;
  const fixed = Number(pool.apy_rate ?? 0);
  return Number.isFinite(fixed) ? fixed : 0;
}

export function apyLabel(pool: Pick<PoolRow, 'apy_rate' | 'dynamic_apy'>): string {
  if (pool.dynamic_apy == null && pool.apy_rate == null) return '—';
  return percent(poolApy(pool));
}

export interface LockState {
  /** Null when the row carries no `lock_end_date`. */
  endsAt: string | null;
  locked: boolean;
  /** 0-100, or null when there is nothing to measure against. */
  progress: number | null;
  label: string;
}

/**
 * Lock state, derived from `lock_end_date` alone.
 *
 * v2 had two answers to this question: `lock_end_date` on the positions and
 * history screens, and `created_at + a hardcoded days-per-token table` on the
 * withdrawals screen. They disagreed, so the same position read "Unlocked" on
 * one page and "82 days left" on another. There is one source here, and the
 * server is asked separately whether a withdrawal is actually permitted.
 */
export function lockState(pool: Pick<PoolRow, 'lock_end_date' | 'created_at'>): LockState {
  const end = pool.lock_end_date ? new Date(pool.lock_end_date).getTime() : Number.NaN;

  if (!Number.isFinite(end)) {
    return { endsAt: null, locked: false, progress: null, label: 'No lock recorded' };
  }

  const now = Date.now();
  if (now >= end) {
    return { endsAt: pool.lock_end_date, locked: false, progress: 100, label: 'Unlocked' };
  }

  const start = pool.created_at ? new Date(pool.created_at).getTime() : Number.NaN;
  const span = Number.isFinite(start) ? end - start : Number.NaN;
  const progress =
    Number.isFinite(span) && span > 0
      ? Math.min(100, Math.max(0, ((now - start) / span) * 100))
      : null;

  const days = Math.ceil((end - now) / 86_400_000);
  const label =
    days >= 30 ? `${Math.floor(days / 30)}mo ${days % 30}d left` : `${days}d left`;

  return { endsAt: pool.lock_end_date, locked: true, progress, label };
}

export function LockProgress({ state }: { state: LockState }) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between gap-3 text-xs">
        <span className={state.locked ? 'text-warning' : 'text-success'}>{state.label}</span>
        <span className="text-muted-foreground">
          {state.endsAt ? shortDate(state.endsAt) : '—'}
        </span>
      </div>
      {state.progress !== null && (
        <div
          role="progressbar"
          aria-label="Lock period elapsed"
          aria-valuenow={Math.round(state.progress)}
          aria-valuemin={0}
          aria-valuemax={100}
          className="h-1.5 w-full overflow-hidden rounded-full bg-elevated"
        >
          <div
            className={cn('h-full rounded-full', state.locked ? 'bg-warning' : 'bg-success')}
            style={{ width: `${state.progress}%` }}
          />
        </div>
      )}
    </div>
  );
}

/** A titled block inside a page. Keeps the four screens visually identical. */
export function Section({
  title,
  description,
  actions,
  children,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="panel">
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border p-5">
        <div className="space-y-1">
          <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
          {description && <p className="text-sm text-muted-foreground">{description}</p>}
        </div>
        {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
      </div>
      {children}
    </section>
  );
}
