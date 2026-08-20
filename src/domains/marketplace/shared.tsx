import { useEffect, useRef, type ReactNode } from 'react';
import { Lock, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { money, token } from '@/lib/format';
import { cn } from '@/lib/utils';

/** Currencies Intl can format as money. Anything else is a token symbol. */
const FIAT = new Set(['EUR', 'USD', 'CHF', 'GBP', 'RON']);

/**
 * Render a price in whatever unit the listing is denominated in.
 *
 * `money()` goes through Intl, which throws on a symbol like `wSTR`, so token
 * denominations are routed to `token()` instead. v2 printed "$" in front of BTC
 * amounts on the domain cards.
 */
export function price(amount: number | null | undefined, currency: string | null | undefined): string {
  if (amount === null || amount === undefined) return '—';
  const code = (currency ?? 'EUR').toUpperCase();
  return FIAT.has(code) ? money(amount, code) : token(amount, code);
}

/** Table/grid loading placeholder, shaped like the rows it replaces. */
export function RowsSkeleton({ rows = 4 }: { rows?: number }) {
  return (
    <div className="space-y-2 p-4">
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} className="h-12 w-full" />
      ))}
    </div>
  );
}

/**
 * An action that has no safe server-side implementation.
 *
 * Rendered visibly disabled with the reason attached, rather than wired to a
 * client-side balance write that RLS drops while the UI claims success. Every
 * use of this carries a TODO naming the server function it is waiting on.
 */
export function BlockedAction({
  label,
  reason,
  className,
}: {
  label: string;
  reason: string;
  className?: string;
}) {
  return (
    <div className={cn('space-y-1.5', className)}>
      <Button variant="secondary" size="sm" disabled aria-describedby={`why-${label}`}>
        <Lock aria-hidden="true" />
        {label}
      </Button>
      <p id={`why-${label}`} className="max-w-xs text-xs text-warning">
        {reason}
      </p>
    </div>
  );
}

/** A labelled block within a page. */
export function Section({
  title,
  description,
  actions,
  children,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
}) {
  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="space-y-0.5">
          <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
          {description && <p className="text-sm text-muted-foreground">{description}</p>}
        </div>
        {actions}
      </div>
      {children}
    </section>
  );
}

/** Segmented control used for the browse and domain tabs. */
export function Tabs<T extends string>({
  value,
  onChange,
  options,
  label,
}: {
  value: T;
  onChange: (next: T) => void;
  options: { value: T; label: string }[];
  label: string;
}) {
  return (
    <div role="tablist" aria-label={label} className="inline-flex gap-1 rounded-lg bg-elevated p-1">
      {options.map((opt) => (
        <button
          key={opt.value}
          role="tab"
          type="button"
          aria-selected={value === opt.value}
          onClick={() => onChange(opt.value)}
          className={cn(
            'rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
            value === opt.value
              ? 'bg-surface text-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground'
          )}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

/**
 * Minimal modal. Closes on Escape and on backdrop click, moves focus into the
 * panel on open, and is labelled by its own title.
 */
export function Modal({
  open,
  onClose,
  title,
  description,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: ReactNode;
}) {
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    panelRef.current?.focus();
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-6">
      <button className="absolute inset-0 bg-overlay/60" onClick={onClose} aria-label="Close dialog" />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        className="panel relative max-h-[90dvh] w-full max-w-lg overflow-y-auto outline-none"
      >
        <div className="flex items-start justify-between gap-4 border-b border-border p-5">
          <div className="space-y-1">
            <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
            {description && <p className="text-sm text-muted-foreground">{description}</p>}
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} aria-label="Close dialog">
            <X />
          </Button>
        </div>
        <div className="space-y-4 p-5">{children}</div>
      </div>
    </div>
  );
}

/** Inline form error, announced to assistive technology when it appears. */
export function FormError({ error }: { error: unknown }) {
  if (!error) return null;
  const message = error instanceof Error ? error.message : String(error);
  return (
    <p role="alert" className="rounded-md bg-danger/10 px-3 py-2 text-sm text-danger">
      {message}
    </p>
  );
}
