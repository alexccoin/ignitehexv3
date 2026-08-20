import { useState, type ReactNode } from 'react';
import { AlertTriangle, Download, Lock, ShieldAlert, Unlock } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';
import type { CoverageReport } from './lib/coverage';
import {
  SAFE_MODE_RELEASE_PHRASE,
  matchesReleasePhrase,
  useSafeMode,
  type RiskLevel,
} from './lib/safeMode';

/**
 * The pieces every screen in the console shares.
 *
 * They live together so the safe-mode treatment, the severity colours and the
 * "this action has no server routine" message are written once. v2 had the
 * safe-mode banner on one page only and each admin screen invented its own
 * confirmation, which is how eight of them ended up with none.
 */

/* ------------------------------------------------------------- severity */

/**
 * One mapping from risk level to tone for the whole domain.
 *
 * The level is always rendered as a word as well as a colour — a red badge and
 * an amber badge are the same badge in greyscale, in forced-colors mode, and to
 * a red-blind reader.
 */
const LEVEL_TONE: Record<RiskLevel, 'danger' | 'warning' | 'info' | 'neutral'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'info',
  low: 'neutral',
};

export function LevelBadge({ level, score }: { level: RiskLevel; score?: number }) {
  return (
    <Badge tone={LEVEL_TONE[level]}>
      {level}
      {score !== undefined && <span className="tabular opacity-70">· {score}</span>}
    </Badge>
  );
}

/* ------------------------------------------------------------- safe mode */

/**
 * The safe-mode banner.
 *
 * Armed is the resting state and the one an administrator should find the
 * console in. Releasing needs the phrase typed exactly; re-arming is one click,
 * because making the safe direction easy and the dangerous direction
 * deliberate is the entire point.
 */
export function SafeModeBanner() {
  const { armed, arm, release } = useSafeMode();
  const [phrase, setPhrase] = useState('');
  const [error, setError] = useState<string | null>(null);

  const onRelease = () => {
    if (!release(phrase)) {
      setError(`Type ${SAFE_MODE_RELEASE_PHRASE} exactly to release safe mode.`);
      return;
    }
    setPhrase('');
    setError(null);
  };

  return (
    <Card
      className={cn(
        'mb-6 border-l-4',
        armed ? 'border-l-primary' : 'border-l-danger'
      )}
    >
      <CardContent className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div className="flex items-start gap-3">
          <span
            className={cn(
              'mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full',
              armed ? 'bg-primary/10 text-primary' : 'bg-danger/10 text-danger'
            )}
          >
            {armed ? <Lock className="size-4" /> : <Unlock className="size-4" />}
          </span>
          <div className="space-y-1">
            <p className="font-medium">{armed ? 'Safe mode armed' : 'Safe mode released'}</p>
            <p className="max-w-2xl text-sm text-muted-foreground">
              {armed
                ? 'Every action that would write to a member balance is blocked. Exposure, risk findings and exports remain available.'
                : 'Actions in this console can now write to member balances. Re-arm as soon as the push is done.'}
            </p>
          </div>
        </div>

        {armed ? (
          <div className="flex flex-col gap-1.5 md:items-end">
            <div className="flex gap-2">
              <Input
                value={phrase}
                onChange={(event) => {
                  setPhrase(event.target.value);
                  setError(null);
                }}
                placeholder={SAFE_MODE_RELEASE_PHRASE}
                aria-label={`Type ${SAFE_MODE_RELEASE_PHRASE} to release safe mode`}
                aria-invalid={error ? true : undefined}
                className="w-56 font-mono"
              />
              <Button
                variant="danger"
                onClick={onRelease}
                disabled={!matchesReleasePhrase(phrase)}
              >
                Release
              </Button>
            </div>
            {error && <p className="text-xs text-danger">{error}</p>}
          </div>
        ) : (
          <Button variant="primary" onClick={arm}>
            <Lock />
            Re-arm safe mode
          </Button>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * The per-action typed confirmation.
 *
 * Releasing safe mode opens the console; this closes the gap between opening it
 * and pressing a specific button. The phrase is typed again for the action
 * itself, so a released console cannot be clicked through by accident, and the
 * value is handed to the mutation which checks it a third time server-side of
 * the button — see `assertPushAllowed`.
 */
export function PhraseConfirm({
  label,
  description,
  onConfirm,
  pending,
  disabled,
  disabledReason,
  variant = 'danger',
}: {
  label: string;
  description?: string;
  onConfirm: (phrase: string) => void;
  pending?: boolean;
  disabled?: boolean;
  disabledReason?: string;
  variant?: 'primary' | 'danger';
}) {
  const { armed } = useSafeMode();
  const [phrase, setPhrase] = useState('');

  const blocked = armed || disabled;
  const reason = armed
    ? 'Safe mode is armed. Release it above before running this.'
    : disabledReason;

  return (
    <div className="space-y-2">
      {description && <p className="text-sm text-muted-foreground">{description}</p>}
      <div className="flex flex-wrap items-center gap-2">
        <Input
          value={phrase}
          onChange={(event) => setPhrase(event.target.value)}
          placeholder={SAFE_MODE_RELEASE_PHRASE}
          aria-label={`Type ${SAFE_MODE_RELEASE_PHRASE} to confirm: ${label}`}
          disabled={blocked || pending}
          className="w-56 font-mono"
        />
        <Button
          variant={variant}
          disabled={blocked || pending || !matchesReleasePhrase(phrase)}
          onClick={() => {
            onConfirm(phrase);
            setPhrase('');
          }}
        >
          {pending ? 'Working…' : label}
        </Button>
      </div>
      {blocked && reason && (
        <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Lock className="size-3" aria-hidden="true" />
          {reason}
        </p>
      )}
    </div>
  );
}

/**
 * An action with no server routine behind it.
 *
 * Rendered rather than omitted, because the gap is worth showing: an
 * administrator looking for "zero this wallet" should learn that it is not
 * possible from the console and why, not conclude the console cannot see the
 * problem. The client will not be taught to do it directly — that is exactly
 * the class of write this rebuild removed.
 */
export function UnavailableAction({
  label,
  reason,
  icon,
}: {
  label: string;
  reason: string;
  icon?: ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Button variant="secondary" disabled aria-describedby={`why-${label.replace(/\W+/g, '-')}`}>
        {icon}
        {label}
      </Button>
      <p
        id={`why-${label.replace(/\W+/g, '-')}`}
        className="flex max-w-md items-start gap-1.5 text-xs text-muted-foreground"
      >
        <AlertTriangle className="mt-0.5 size-3 shrink-0" aria-hidden="true" />
        {reason}
      </p>
    </div>
  );
}

/* ---------------------------------------------------------------- export */

/** Hand a generated CSV to the browser as a download. */
export function downloadCsv(filename: string, contents: string): void {
  const blob = new Blob([contents], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

export function ExportButton({
  onExport,
  disabled,
  label = 'Export CSV',
}: {
  onExport: () => void;
  disabled?: boolean;
  label?: string;
}) {
  return (
    <Button variant="secondary" onClick={onExport} disabled={disabled}>
      <Download />
      {label}
    </Button>
  );
}

/* -------------------------------------------------------------- coverage */

/**
 * What the sweep actually managed to read.
 *
 * A total is only as good as its coverage, so the two are always shown
 * together. A truncated table means the figure on screen is a LOWER BOUND, and
 * that has to be said in those words — v2 stopped at forty pages silently, and
 * a quietly short read of an asset table understates platform exposure.
 */
export function ScanCoverage({
  scannedTables,
  scannedRows,
  truncatedTables,
  coverage,
  errors,
  ranAt,
}: {
  scannedTables: string[];
  scannedRows: number;
  truncatedTables: string[];
  coverage?: CoverageReport;
  errors: string[];
  ranAt: string;
}) {
  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        {scannedRows.toLocaleString()} rows across {scannedTables.length} tables · last run{' '}
        {new Date(ranAt).toLocaleString()}
      </p>

      {/*
        A short read is not the page budget running out — that is
        `truncatedTables` below. This is RLS: an authorised SELECT over rows the
        caller may not see returns 200 and an empty set, so before the counts
        RPC existed a table the admin could not read looked exactly like a table
        with nothing in it, and the console printed one member's holdings as the
        platform's (F-034).
      */}
      {coverage?.verified && coverage.short.length > 0 && (
        <div className="flex items-start gap-2 rounded-md bg-danger/10 p-3 text-sm text-danger">
          <ShieldAlert className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <div className="space-y-1">
            <p>
              <span className="font-medium">
                This sweep was not allowed to read {coverage.missedRows.toLocaleString()} row
                {coverage.missedRows === 1 ? '' : 's'}.
              </span>{' '}
              Every figure below covers only the rows row-level security returned, which is fewer
              than the rows that exist. It is not an empty platform — it is a partial view.
            </p>
            <ul className="ml-4 list-disc">
              {coverage.short.map((t) => (
                <li key={t.table}>
                  <span className="font-mono">{t.table}</span> — read {t.read.toLocaleString()} of{' '}
                  {(t.total ?? 0).toLocaleString()}
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {coverage && !coverage.verified && (
        <div className="flex items-start gap-2 rounded-md bg-warning/10 p-3 text-sm text-warning">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <p>
            <span className="font-medium">Coverage could not be checked</span>, so there is no
            evidence these totals are complete — only that nothing errored.
            {coverage.error ? ` (${coverage.error})` : ''}
          </p>
        </div>
      )}

      {coverage?.verified && coverage.short.length === 0 && coverage.unverified.length === 0 && (
        <p className="text-sm text-muted-foreground">
          Coverage verified: every swept table returned all of its rows.
        </p>
      )}

      {coverage?.verified && coverage.unverified.length > 0 && (
        <div className="flex items-start gap-2 rounded-md bg-warning/10 p-3 text-sm text-warning">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <p>
            <span className="font-medium">
              {coverage.unverified.length} table(s) have no authoritative count
            </span>
            , so whether they were read whole is unknown: {coverage.unverified.join(', ')}
          </p>
        </div>
      )}

      {truncatedTables.length > 0 && (
        <div className="flex items-start gap-2 rounded-md bg-danger/10 p-3 text-sm text-danger">
          <ShieldAlert className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <p>
            <span className="font-medium">These totals are a lower bound.</span> The page budget ran
            out on {truncatedTables.join(', ')}, so rows beyond it were not read and the exposure
            shown is smaller than the truth.
          </p>
        </div>
      )}

      {errors.length > 0 && (
        <div className="flex items-start gap-2 rounded-md bg-warning/10 p-3 text-sm text-warning">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
          <p>
            <span className="font-medium">{errors.length} table(s) could not be read</span>, so
            their assets are missing from every figure here: {errors.slice(0, 4).join(' · ')}
          </p>
        </div>
      )}
    </div>
  );
}

/**
 * Quantities the console cannot value in USD, printed in their own units.
 *
 * There is no FX source in this system and no rate for pool types like
 * `domain`, so EUR, CHF, GBP and those pools have no dollar figure. They used
 * to get one anyway — EUR, CHF and GBP were counted as 1.00 USD each, and every
 * unrecognised symbol was priced at the STR rate. Showing the raw quantity next
 * to the USD total is the honest replacement: the holding is visible, and no
 * number is claimed for it that no source stands behind.
 */
export function UnpricedList({
  items,
  className,
}: {
  items: { unit: string; amount: number }[];
  className?: string;
}) {
  if (items.length === 0) return null;

  return (
    <span className={className ?? 'block text-xs font-medium text-warning'}>
      {items
        .map((item) => `${item.amount.toLocaleString('en-IE', { maximumFractionDigits: 2 })} ${item.unit}`)
        .join(' · ')}{' '}
      unconverted
    </span>
  );
}
