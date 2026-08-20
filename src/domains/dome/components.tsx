import { useEffect, useId, useRef, type ReactNode } from 'react';
import { Bell, CheckCheck, Inbox, X } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { relativeTime, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { TOTAL_SUPPLY, useMarkNoticeRead, useNotices, type AllocationRecord, type EquityMetrics } from './hooks';

/**
 * The pieces both Dome screens share.
 *
 * The prototype's visual ideas survive here — the bento of panels, the
 * milestone track, the two-bar comparison, the modal anatomy of
 * header / summary strip / scrollable body / disclaimer. Its stylesheet does
 * not: `dashboard.css` was 4,069 lines defining `dash-modal`, `section-card`,
 * `small-chip`, `status-tag`, `bar-track` and around two hundred more classes,
 * each with its own hardcoded hex. Every one of those is expressed below with
 * v3's semantic tokens and existing primitives, so the Dome inherits the app's
 * light and dark palettes instead of shipping a fifth competing one.
 */

/* ----------------------------------------------------------- formatting */

/** SAFE and private placements are denominated in USD, not the app default. */
export const usd = (amount: number | null | undefined, digits = 0): string =>
  new Intl.NumberFormat('en-IE', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(Number(amount ?? 0));

/** A plain count — shares are not money and must not carry a currency mark. */
export const count = (value: number | null | undefined, digits = 0): string =>
  new Intl.NumberFormat('en-IE', { maximumFractionDigits: digits }).format(Number(value ?? 0));

/**
 * Ownership percentage.
 *
 * Small holdings round to 0.000% at three decimals, which reads as "you own
 * nothing", so anything below a thousandth of a percent gets more digits.
 */
export const ownershipPct = (value: number): string =>
  value === 0 ? '0%' : value >= 0.001 ? `${value.toFixed(3)}%` : `${value.toFixed(6)}%`;

/** The denominator behind every ownership figure, stated wherever one appears. */
export const SUPPLY_NOTE = `of ${count(TOTAL_SUPPLY)} total shares`;

/* -------------------------------------------------------------- primitives */

/** Table and list loading placeholder, shaped like the rows it replaces. */
export function RowsSkeleton({ rows = 4, className }: { rows?: number; className?: string }) {
  return (
    <div className={cn('space-y-2 p-5', className)}>
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} className="h-12 w-full" />
      ))}
    </div>
  );
}

/** A label/value row inside a summary box. */
export function MetricRow({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
}) {
  return (
    <div className="flex items-baseline justify-between gap-4 border-b border-border py-2 last:border-0">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className="text-right">
        <span className="tabular text-sm font-medium">{value}</span>
        {hint && <span className="block text-xs text-muted-foreground">{hint}</span>}
      </span>
    </div>
  );
}

/**
 * One bar in a two-bar comparison.
 *
 * The prototype filled these from CSS classes with baked-in widths, so the two
 * bars showed the same ratio for every member. Here the width is the ratio, and
 * the figure is printed beside it so the bar is decoration rather than the only
 * way to read the value.
 */
export function ComparisonBar({
  label,
  value,
  max,
  emphasis = false,
}: {
  label: string;
  value: number;
  max: number;
  emphasis?: boolean;
}) {
  const ratio = max > 0 ? Math.min(Math.max(value / max, 0), 1) : 0;
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-sm text-muted-foreground">{label}</span>
        <span className="tabular text-sm font-semibold">{count(value)}</span>
      </div>
      <div
        className="h-2 w-full overflow-hidden rounded-full bg-elevated"
        role="img"
        aria-label={`${label}: ${count(value)} shares`}
      >
        <span
          className={cn('block h-full rounded-full', emphasis ? 'bg-primary' : 'bg-accent')}
          style={{ width: `${(ratio * 100).toFixed(2)}%` }}
        />
      </div>
    </div>
  );
}

export interface Milestone {
  id: string;
  title: string;
  detail: string;
  date: string;
}

/**
 * The prototype's "status track" — a row of nodes joined by lines.
 *
 * The original hardcoded four named tiers (Origin, Signal, Ascend, Apex) with
 * the fourth always lit. There is no tier column in the database and no
 * threshold table, so inventing one here would repeat exactly the mistake this
 * port exists to fix. The track instead plots the member's own settled
 * allocations in order, which is real, and is empty when there are none.
 */
export function MilestoneTrack({ milestones }: { milestones: Milestone[] }) {
  if (milestones.length === 0) {
    return (
      <EmptyState
        title="No allocations on file"
        description="Your track fills in as allocations are recorded against your file."
      />
    );
  }

  return (
    <ol className="flex flex-wrap items-start gap-y-4">
      {milestones.map((m, i) => (
        <li key={m.id} className="flex min-w-[8rem] flex-1 items-start gap-3">
          {i > 0 && <span aria-hidden="true" className="mt-4 h-px flex-1 bg-border" />}
          <div className="space-y-1">
            <span
              aria-hidden="true"
              className={cn(
                'flex size-8 items-center justify-center rounded-full text-xs font-semibold',
                i === milestones.length - 1
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-elevated text-muted-foreground'
              )}
            >
              {i + 1}
            </span>
            <p className="text-sm font-medium leading-tight">{m.title}</p>
            <p className="text-xs text-muted-foreground">{m.detail}</p>
            <p className="text-xs text-muted-foreground">{shortDate(m.date)}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}

/* ------------------------------------------------------------------ modal */

const FOCUSABLE =
  'a[href],button:not([disabled]),textarea:not([disabled]),input:not([disabled]),select:not([disabled]),[tabindex]:not([tabindex="-1"])';

/**
 * The Dome modal.
 *
 * Traps focus, closes on Escape and on an overlay click, restores focus to
 * whatever opened it, and locks the page behind it. `role="dialog"` and
 * `aria-modal="true"` are on the panel, labelled by its own heading.
 *
 * The prototype's version was a permanently mounted div toggled with an
 * `is-open` class and `aria-hidden`, which leaves every control inside it in
 * the tab order while the dialog is "closed". This one unmounts.
 */
export function DomeModal({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  wide = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: ReactNode;
  footer?: ReactNode;
  wide?: boolean;
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const restoreRef = useRef<HTMLElement | null>(null);
  const titleId = useId();
  const descId = useId();

  useEffect(() => {
    if (!open) return;

    restoreRef.current = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const onKey = (event: KeyboardEvent) => {
      const panel = panelRef.current;
      if (event.key === 'Escape') {
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key !== 'Tab' || !panel) return;

      const nodes = Array.from(panel.querySelectorAll<HTMLElement>(FOCUSABLE));
      if (nodes.length === 0) {
        event.preventDefault();
        panel.focus();
        return;
      }
      const first = nodes[0];
      const last = nodes[nodes.length - 1];
      const active = document.activeElement;

      // Wrap in both directions, and pull focus back in if it has escaped the
      // panel entirely (which it has on the very first Tab, from the panel).
      if (event.shiftKey && (active === first || active === panel || !panel.contains(active))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (active === last || !panel.contains(active))) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKey, true);
    const focusTimer = window.setTimeout(() => {
      const panel = panelRef.current;
      const nodes = panel?.querySelectorAll<HTMLElement>(FOCUSABLE);
      (nodes && nodes.length ? nodes[0] : panel)?.focus();
    }, 0);

    return () => {
      document.removeEventListener('keydown', onKey, true);
      window.clearTimeout(focusTimer);
      document.body.style.overflow = previousOverflow;
      restoreRef.current?.focus();
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-6">
      <button
        type="button"
        tabIndex={-1}
        className="absolute inset-0 bg-overlay/60"
        onClick={onClose}
        aria-label="Close dialog"
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={description ? descId : undefined}
        tabIndex={-1}
        className={cn(
          'panel relative flex max-h-[90dvh] w-full flex-col overflow-hidden outline-none',
          wide ? 'max-w-3xl' : 'max-w-lg'
        )}
      >
        <div className="flex items-start justify-between gap-4 border-b border-border p-5">
          <div className="space-y-1">
            <h2 id={titleId} className="text-lg font-semibold tracking-tight">
              {title}
            </h2>
            {description && (
              <p id={descId} className="text-sm text-muted-foreground">
                {description}
              </p>
            )}
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} aria-label="Close dialog">
            <X />
          </Button>
        </div>
        <div className="flex-1 space-y-4 overflow-y-auto p-5">{children}</div>
        {footer && <div className="border-t border-border p-5 text-xs text-muted-foreground">{footer}</div>}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------ round terms */

/**
 * The prototype's "Seed Round Package Descriptions" modal, rebuilt.
 *
 * The original listed eleven packages — Origin Spark at $250 through Genesis
 * Crown at $100,000, each with a share count, an inventory count and a
 * quarterly-dividend promise from a fixed date. None of it came from anywhere;
 * it was an array literal in the component, and no table in this schema
 * publishes a package catalogue, an inventory or a listing date.
 *
 * What survives is the anatomy — header, three-figure summary strip,
 * scrollable body of cards, disclaimer — filled with the terms actually
 * recorded against this member: what they paid per share, on which programme,
 * and what the most recent recorded price was. A member with no allocations
 * gets an empty state, not a brochure.
 */
export function RoundTermsModal({
  open,
  onClose,
  metrics,
}: {
  open: boolean;
  onClose: () => void;
  metrics: EquityMetrics;
}) {
  return (
    <DomeModal
      open={open}
      onClose={onClose}
      wide
      title="Your round terms"
      description="Every allocation recorded against your file, and the prices behind it."
      footer={
        <>
          Figures are read from your own allocation records. Share value is indicative: it applies the
          most recently recorded price per share to your holding, and no trading venue is implied by
          it. There is no published package catalogue, inventory count or listing date in this system,
          so none is shown.
        </>
      }
    >
      {metrics.counted.length === 0 ? (
        <EmptyState
          title="No allocations recorded"
          description="Nothing has been booked against your file yet, so there are no round terms to show."
        />
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="rounded-lg bg-elevated p-4">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Average paid</p>
              <p className="tabular mt-1 text-xl font-semibold">
                {metrics.avgPrice > 0 ? usd(metrics.avgPrice, 3) : '—'}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">per share, across settled records</p>
            </div>
            <div className="rounded-lg bg-elevated p-4">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Latest recorded</p>
              <p className="tabular mt-1 text-xl font-semibold">
                {metrics.hasPricedRound ? usd(metrics.latestPrice, 3) : '—'}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">price on your most recent record</p>
            </div>
            <div className="rounded-lg bg-elevated p-4">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Your holding</p>
              <p className="tabular mt-1 text-xl font-semibold">{count(metrics.shares)}</p>
              <p className="mt-1 text-xs text-muted-foreground">
                {ownershipPct(metrics.ownership)} {SUPPLY_NOTE}
              </p>
            </div>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            {metrics.records.map((record) => (
              <article
                key={record.id}
                className={cn(
                  'rounded-lg border p-4',
                  record.counted ? 'border-border' : 'border-border bg-elevated/40'
                )}
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-medium">{record.programme}</p>
                    <p className="text-xs text-muted-foreground">{shortDate(record.date)}</p>
                  </div>
                  <StatusBadge status={record.status} />
                </div>
                <div className="mt-3 space-y-0.5">
                  <MetricRow label="Shares" value={count(record.shares + record.bonusShares)} />
                  <MetricRow
                    label="Price per share"
                    value={record.pricePerShare > 0 ? usd(record.pricePerShare, 3) : '—'}
                  />
                  <MetricRow
                    label="Invested"
                    value={record.invested > 0 ? usd(record.invested) : '—'}
                  />
                </div>
                {!record.counted && (
                  <p className="mt-3 text-xs text-warning">
                    Excluded from your totals — this record never settled.
                  </p>
                )}
              </article>
            ))}
          </div>

          {metrics.wnftShares > 0 && (
            <p className="text-xs text-muted-foreground">
              {count(metrics.wnftShares)} wNFT shares are also counted in your holding. Your share
              ledger carries no price for them, so they contribute to the share count but not to the
              invested total or the average paid price.
            </p>
          )}
        </>
      )}
    </DomeModal>
  );
}

/** Detail for a single allocation, opened from the portfolio table. */
export function AllocationDetailModal({
  record,
  onClose,
}: {
  record: AllocationRecord | null;
  onClose: () => void;
}) {
  return (
    <DomeModal
      open={!!record}
      onClose={onClose}
      title={record ? `${record.programme} allocation` : 'Allocation'}
      description={record ? shortDate(record.date) : undefined}
    >
      {record && (
        <>
          <div className="flex items-center justify-between gap-3">
            <span className="text-sm text-muted-foreground">Status</span>
            <StatusBadge status={record.status} />
          </div>
          <div className="space-y-0.5">
            <MetricRow label="Shares" value={count(record.shares)} />
            {record.bonusShares > 0 && (
              <MetricRow label="Bonus shares" value={count(record.bonusShares)} />
            )}
            <MetricRow
              label="Price per share"
              value={record.pricePerShare > 0 ? usd(record.pricePerShare, 3) : '—'}
            />
            <MetricRow label="Invested" value={record.invested > 0 ? usd(record.invested) : '—'} />
            <MetricRow
              label="Counts toward totals"
              value={record.counted ? 'Yes' : 'No — did not settle'}
            />
          </div>
          {record.reference && (
            <div className="space-y-1">
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Reference</p>
              <p className="tabular break-all rounded-md bg-elevated p-3 text-xs">{record.reference}</p>
            </div>
          )}
        </>
      )}
    </DomeModal>
  );
}

/* ---------------------------------------------------------------- notices */

/**
 * The prototype's notifications dropdown, as a panel.
 *
 * Kept as a panel rather than a floating dropdown: the original positioned
 * itself with hand-computed `--notif-top` / `--notif-left` custom properties
 * recalculated on every scroll and resize, which the shell's own header already
 * makes unnecessary. The content is the member's own `user_messages` rows.
 */
export function NoticesPanel() {
  const notices = useNotices(6);
  const markRead = useMarkNoticeRead();
  const unread = (notices.data ?? []).filter((n) => !n.is_read).length;

  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="text-base">Notices</CardTitle>
          <CardDescription>Messages addressed to your file.</CardDescription>
        </div>
        {unread > 0 && <Badge tone="primary">{unread} unread</Badge>}
      </CardHeader>
      <CardContent className="p-0">
        {notices.isLoading ? (
          <RowsSkeleton rows={3} />
        ) : notices.isError ? (
          <ErrorState error={notices.error} onRetry={() => void notices.refetch()} />
        ) : (notices.data ?? []).length === 0 ? (
          <EmptyState
            title="No notices"
            description="Nothing has been sent to you yet."
            icon={<Bell className="size-5" />}
          />
        ) : (
          <ul className="divide-y divide-border">
            {(notices.data ?? []).map((notice) => (
              <li key={notice.id} className="flex items-start gap-3 p-4">
                <span
                  aria-hidden="true"
                  className={cn(
                    'mt-1.5 size-2 shrink-0 rounded-full',
                    notice.is_read ? 'bg-border' : 'bg-primary'
                  )}
                />
                <div className="min-w-0 flex-1 space-y-0.5">
                  <p className="text-sm font-medium leading-tight">{notice.subject}</p>
                  <p className="line-clamp-2 text-xs text-muted-foreground">{notice.message}</p>
                  <p className="text-xs text-muted-foreground">{relativeTime(notice.created_at)}</p>
                </div>
                {!notice.is_read && (
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Mark "${notice.subject}" as read`}
                    disabled={markRead.isPending}
                    onClick={() => markRead.mutate(notice.id)}
                  >
                    <CheckCheck />
                  </Button>
                )}
              </li>
            ))}
          </ul>
        )}
        {markRead.isError && (
          <p role="alert" className="m-4 rounded-md bg-danger/10 px-3 py-2 text-sm text-danger">
            {markRead.error instanceof Error ? markRead.error.message : 'Could not update that notice.'}
          </p>
        )}
      </CardContent>
    </Card>
  );
}

/* ------------------------------------------------------------- activity */

export interface ActivityEntry {
  id: string;
  title: string;
  detail: string;
  date: string;
}

/** The prototype's "Recent Activity" feed, over rows that actually exist. */
export function ActivityFeed({
  entries,
  loading,
  error,
  onRetry,
}: {
  entries: ActivityEntry[];
  loading?: boolean;
  error?: unknown;
  onRetry?: () => void;
}) {
  if (loading) return <RowsSkeleton rows={4} />;
  if (error) return <ErrorState error={error} onRetry={onRetry} />;
  if (entries.length === 0) {
    return (
      <EmptyState
        title="Nothing has happened yet"
        description="Allocations, staking positions and transfers appear here as they are recorded."
        icon={<Inbox className="size-5" />}
      />
    );
  }

  return (
    <ul className="divide-y divide-border">
      {entries.map((entry) => (
        <li key={entry.id} className="flex items-start gap-3 p-4">
          <span aria-hidden="true" className="mt-1.5 size-2 shrink-0 rounded-full bg-accent" />
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium leading-tight">{entry.title}</p>
            <p className="text-xs text-muted-foreground">
              {entry.detail} · {shortDate(entry.date)}
            </p>
          </div>
        </li>
      ))}
    </ul>
  );
}
