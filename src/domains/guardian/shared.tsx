import type { ReactNode } from 'react';
import { ExternalLink, Lock } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';

/**
 * Pieces shared by the four guardian screens.
 *
 * `LockedAction` is the important one: a control the platform cannot honour yet
 * is rendered visibly disabled with the reason next to it, rather than wired to
 * a table update that fakes the outcome. v2's guardian console approved
 * withdrawals by writing `status = 'approved'` from the browser and showing a
 * success toast, which told an operator that money had been sent when nothing
 * had left any wallet.
 */
export function LockedAction({
  label,
  reason,
  icon,
  className,
}: {
  label: string;
  reason: string;
  icon?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-wrap items-center gap-3', className)}>
      <Button variant="secondary" size="sm" disabled title={reason}>
        {icon ?? <Lock aria-hidden="true" />}
        {label}
      </Button>
      <p className="min-w-[12rem] flex-1 text-xs text-muted-foreground">{reason}</p>
    </div>
  );
}

/** A short label/value pair, used inside detail panels. */
export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="space-y-0.5">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="tabular text-sm font-medium">{value}</div>
    </div>
  );
}

/** Truncate a chain address to something a person can compare at a glance. */
export function shortAddress(address: string | null | undefined): string {
  if (!address) return '—';
  return address.length > 20 ? `${address.slice(0, 10)}…${address.slice(-6)}` : address;
}

/** A link out to a block explorer so a figure on screen can be checked. */
export function MempoolLink({ address, label }: { address: string; label?: string }) {
  return (
    <a
      href={`https://mempool.space/address/${encodeURIComponent(address)}`}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex items-center gap-1 text-xs text-primary hover:underline"
    >
      {label ?? 'Verify'}
      <ExternalLink className="size-3" aria-hidden="true" />
    </a>
  );
}

const SEVERITY_TONES: Record<string, 'neutral' | 'info' | 'warning' | 'danger'> = {
  low: 'info',
  medium: 'warning',
  high: 'warning',
  critical: 'danger',
};

/** Alert severity as a badge, using the same tone scale as the rest of the app. */
export function SeverityBadge({ severity }: { severity: string }) {
  const key = severity.toLowerCase();
  return (
    <Badge tone={SEVERITY_TONES[key] ?? 'neutral'}>
      {key.charAt(0).toUpperCase() + key.slice(1)}
    </Badge>
  );
}

/** BTC amount at chain precision. Not `money()` — BTC is not a currency Intl knows. */
export function btc(amount: number | null | undefined): string {
  // Null is NOT zero. `btc-wallet-balances` returns null for an address it
  // could not read, and "0.0000 BTC" on a proof-of-reserve page is
  // indistinguishable from an emptied reserve.
  if (amount === null || amount === undefined || !Number.isFinite(Number(amount))) {
    return 'Unavailable';
  }
  return `${Number(amount).toLocaleString('en-IE', {
    minimumFractionDigits: 4,
    maximumFractionDigits: 8,
  })} BTC`;
}

/** Whole hours left on a processing window, floored at zero. */
export function hoursUntil(iso: string | null | undefined): number | null {
  if (!iso) return null;
  const ms = new Date(iso).getTime() - Date.now();
  if (!Number.isFinite(ms)) return null;
  return Math.max(0, Math.round(ms / 3_600_000));
}
