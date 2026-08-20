import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Eye, History, RefreshCw, Scale, Undo2, Wallet } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, percent, relativeTime } from '@/lib/format';
import {
  useCorrectPositions,
  useCorrectionLog,
  useExposureIndex,
  useRevertCorrection,
} from './hooks';
import { MIN_EXPOSURE_USD, type ExposureRow } from './lib/platformExposure';
import {
  LevelBadge,
  PhraseConfirm,
  SafeModeBanner,
  UnavailableAction,
} from './components';

/**
 * Unbacked-position correction.
 *
 * An unbacked position is a balance sitting in `user_staking_pools`,
 * `user_str_shares` or `vesting_tokens` that no admin decision put there: no
 * credited voucher, no credited raise, no admin-approved staking request. The
 * platform is carrying it as a liability to the member with nothing on record
 * granting it.
 *
 * Correcting one scales those three stores down to the admin-credited value.
 * That is the most consequential action in the entire console, so:
 *
 *  - the scale factor is computed from figures the sweep produced, but the
 *    arithmetic on the balances happens inside
 *    `admin_correct_unbacked_positions`, which reads the current rows, writes
 *    the originals into `v2_admin_actions.before_data` and only then scales;
 *  - a dry run is available while safe mode is still armed, so an
 *    administrator can see the effect before unlocking anything;
 *  - the real run needs the phrase typed for that specific action;
 *  - every correction is reversible from the log below, because the originals
 *    were stored before anything moved.
 */

const usdFormat = (value: number) => money(value, 'USD');
const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error ? error.message : fallback;

/** Below this an unbacked position is not worth an intervention. */
const MATERIAL_UNBACKED_USD = 10_000;

function scaleFor(row: ExposureRow): number {
  if (row.positionsUsd <= 0) return 1;
  return Math.max(0, Math.min(1, row.adminCreditedUsd / row.positionsUsd));
}

function reasonFor(row: ExposureRow): string {
  return `Risk console correction — positions ${usdFormat(row.positionsUsd)}, admin credit ${usdFormat(row.adminCreditedUsd)}, unbacked ${usdFormat(row.unbackedUsd)}`;
}

export default function Corrections() {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);

  const exposure = useExposureIndex(MIN_EXPOSURE_USD);
  const log = useCorrectionLog();
  const correct = useCorrectPositions();
  const revert = useRevertCorrection();

  const candidates = useMemo(
    () =>
      (exposure.data?.rows ?? [])
        .filter((row) => row.unbackedUsd >= MATERIAL_UNBACKED_USD && row.positionsUsd > 0)
        .sort((a, b) => b.unbackedUsd - a.unbackedUsd),
    [exposure.data]
  );

  const selectedRows = useMemo(
    () => candidates.filter((row) => selected.has(row.userId)),
    [candidates, selected]
  );

  const totals = useMemo(() => {
    const unbacked = candidates.reduce((sum, row) => sum + row.unbackedUsd, 0);
    const selectedUnbacked = selectedRows.reduce((sum, row) => sum + row.unbackedUsd, 0);
    const uncredited = candidates.filter((row) => row.adminCreditedUsd <= 0).length;
    return { unbacked, selectedUnbacked, uncredited };
  }, [candidates, selectedRows]);

  const toggleRow = (userId: string) =>
    setSelected((previous) => {
      const next = new Set(previous);
      if (next.has(userId)) next.delete(userId);
      else next.add(userId);
      return next;
    });

  const preview = (row: ExposureRow) => {
    correct.mutate(
      {
        userId: row.userId,
        scale: scaleFor(row),
        reason: reasonFor(row),
        dryRun: true,
        confirmation: '',
      },
      {
        onSuccess: (outcome) =>
          toast.success(`${row.name}: dry run complete.`, {
            description: `Positions would be scaled to ${percent(outcome.scale * 100, 1)} of their current value, removing ${usdFormat(row.unbackedUsd)}.`,
          }),
        onError: (error) => toast.error(errorMessage(error, 'The dry run failed.')),
      }
    );
  };

  const correctOne = (row: ExposureRow, phrase: string) => {
    correct.mutate(
      {
        userId: row.userId,
        scale: scaleFor(row),
        reason: reasonFor(row),
        dryRun: false,
        confirmation: phrase,
      },
      {
        onSuccess: () => {
          setSelected((previous) => {
            const next = new Set(previous);
            next.delete(row.userId);
            return next;
          });
          toast.success(`${row.name}: positions scaled to the admin-credited value.`);
        },
        onError: (error) => toast.error(errorMessage(error, 'The correction was refused.')),
      }
    );
  };

  /**
   * Correct many accounts.
   *
   * Sequential, not parallel: `admin_correct_unbacked_positions` writes to the
   * same balance tables for every target, and six of those in flight at once is
   * six transactions racing for the same rows. v2 fired them in batches of six.
   * A failure stops the run and leaves the remainder selected, so the operator
   * knows exactly where it got to instead of having to diff the log.
   */
  const correctSelected = async (phrase: string) => {
    const targets = [...selectedRows];
    if (targets.length === 0) return;

    setProgress({ done: 0, total: targets.length });
    const remaining = new Set(targets.map((row) => row.userId));

    for (const [index, row] of targets.entries()) {
      try {
        await correct.mutateAsync({
          userId: row.userId,
          scale: scaleFor(row),
          reason: reasonFor(row),
          dryRun: false,
          confirmation: phrase,
        });
        remaining.delete(row.userId);
        setProgress({ done: index + 1, total: targets.length });
      } catch (error) {
        setSelected(remaining);
        setProgress(null);
        toast.error(errorMessage(error, 'The correction was refused.'), {
          description: `${index} of ${targets.length} corrected. The rest are still selected.`,
        });
        return;
      }
    }

    setSelected(new Set());
    setProgress(null);
    toast.success(`${targets.length} account(s) corrected.`);
  };

  return (
    <>
      <PageHeader
        title="Position corrections"
        description="Scale staking, $STR shares and vesting down to what an administrator actually credited."
        actions={
          <Button
            variant="ghost"
            size="icon"
            aria-label="Re-run the exposure sweep"
            onClick={() => void exposure.refetch()}
            disabled={exposure.isFetching}
          >
            <RefreshCw className={exposure.isFetching ? 'animate-spin' : ''} />
          </Button>
        }
      />

      <SafeModeBanner />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Unbacked value"
          value={usdFormat(totals.unbacked)}
          sub={`Across ${candidates.length} account(s)`}
          loading={exposure.isLoading}
          tone={totals.unbacked > 0 ? 'danger' : 'default'}
        />
        <Stat
          label="With no credit at all"
          value={totals.uncredited}
          sub="Nothing on record granted these positions"
          loading={exposure.isLoading}
          tone={totals.uncredited > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Selected"
          value={usdFormat(totals.selectedUnbacked)}
          sub={`${selectedRows.length} account(s)`}
          loading={exposure.isLoading}
        />
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Accounts carrying unbacked positions</CardTitle>
            <CardDescription>
              Positions worth at least {usdFormat(MATERIAL_UNBACKED_USD)} more than the admin credit
              behind them.
            </CardDescription>
          </div>
        </CardHeader>

        <CardContent className="space-y-4">
          <div className="flex flex-wrap items-center gap-2 rounded-md bg-elevated p-3">
            <span className="mr-1 text-sm font-medium">
              {progress
                ? `Correcting ${progress.done}/${progress.total}`
                : `${selectedRows.length} selected`}
            </span>
            <Button
              size="sm"
              variant="outline"
              disabled={candidates.length === 0 || correct.isPending}
              onClick={() => setSelected(new Set(candidates.map((row) => row.userId)))}
            >
              Select all
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={selected.size === 0 || correct.isPending}
              onClick={() => setSelected(new Set())}
            >
              Clear
            </Button>
          </div>

          <PhraseConfirm
            label={`Correct ${selectedRows.length} account(s)`}
            description={`Removes ${usdFormat(totals.selectedUnbacked)} of unbacked value. Each account's original staking, share and vesting values are stored first and can be restored from the log below.`}
            pending={correct.isPending}
            disabled={selectedRows.length === 0}
            disabledReason="Select at least one account."
            onConfirm={(phrase) => void correctSelected(phrase)}
          />
        </CardContent>

        <CardContent className="p-0">
          {exposure.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-64 w-full" />
            </div>
          ) : exposure.isError ? (
            <ErrorState error={exposure.error} onRetry={() => void exposure.refetch()} />
          ) : candidates.length === 0 ? (
            <EmptyState
              title="Nothing to correct"
              description="Every position above the threshold is backed by an admin credit."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH className="w-8" />
                    <TH>Risk</TH>
                    <TH>Member</TH>
                    <TH className="text-right">Positions</TH>
                    <TH className="text-right">Admin credit</TH>
                    <TH className="text-right">Unbacked</TH>
                    <TH className="text-right">Scale to</TH>
                    <TH className="text-right">Action</TH>
                  </TR>
                </THead>
                <TBody>
                  {candidates.map((row) => (
                    <TR key={row.userId}>
                      <TD>
                        <input
                          type="checkbox"
                          className="size-4 rounded border-border accent-primary"
                          checked={selected.has(row.userId)}
                          onChange={() => toggleRow(row.userId)}
                          aria-label={`Select ${row.name}`}
                        />
                      </TD>
                      <TD>
                        <LevelBadge level={row.level} score={row.score} />
                      </TD>
                      <TD>
                        <p className="font-medium">{row.name}</p>
                        <p className="text-xs text-muted-foreground">{row.email}</p>
                        <p className="font-mono text-xs text-muted-foreground">
                          {row.userId.slice(0, 8)}…
                        </p>
                      </TD>
                      <TD className="tabular text-right">{usdFormat(row.positionsUsd)}</TD>
                      <TD className="tabular text-right">
                        {row.adminCreditedUsd > 0 ? (
                          usdFormat(row.adminCreditedUsd)
                        ) : (
                          <Badge tone="danger">None</Badge>
                        )}
                      </TD>
                      <TD className="tabular text-right font-medium text-danger">
                        {usdFormat(row.unbackedUsd)}
                      </TD>
                      <TD className="tabular text-right">{percent(scaleFor(row) * 100, 1)}</TD>
                      <TD>
                        <div className="flex items-center justify-end gap-2">
                          <Button
                            size="sm"
                            variant="ghost"
                            aria-label={`Dry run the correction for ${row.name}`}
                            disabled={correct.isPending}
                            onClick={() => preview(row)}
                          >
                            <Eye />
                          </Button>
                          <PhraseConfirm
                            label="Correct"
                            pending={correct.isPending}
                            onConfirm={(phrase) => correctOne(row, phrase)}
                          />
                        </div>
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2 lg:items-start">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <History className="size-4" aria-hidden="true" />
                Correction log
              </CardTitle>
              <CardDescription>
                Each entry holds the exact staking, share and vesting values from before the
                correction, which is what makes the revert possible.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {log.isLoading ? (
              <Skeleton className="h-40 w-full" />
            ) : log.isError ? (
              <ErrorState error={log.error} onRetry={() => void log.refetch()} />
            ) : (log.data ?? []).length === 0 ? (
              <EmptyState
                title="No corrections yet"
                description="Nothing has been scaled down from this console."
              />
            ) : (
              (log.data ?? []).map((entry) => (
                <div key={entry.id} className="space-y-2 rounded-md border border-border p-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <Badge tone={entry.action === 'revert_correction' ? 'info' : 'warning'}>
                      {entry.action === 'revert_correction' ? 'Reverted' : 'Corrected'}
                    </Badge>
                    <span className="text-xs text-muted-foreground">
                      {relativeTime(entry.created_at)}
                    </span>
                  </div>
                  <p className="break-words text-xs text-muted-foreground">{entry.notes ?? '—'}</p>
                  <p className="font-mono text-xs text-muted-foreground">
                    member {entry.user_id ?? '—'}
                  </p>
                  {entry.action !== 'revert_correction' && (
                    <PhraseConfirm
                      label="Revert"
                      description="Restores the positions recorded before this correction."
                      pending={revert.isPending}
                      onConfirm={(phrase) =>
                        revert.mutate(
                          { actionId: entry.id, confirmation: phrase },
                          {
                            onSuccess: () => toast.success('Original positions restored.'),
                            onError: (error) =>
                              toast.error(errorMessage(error, 'The revert was refused.')),
                          }
                        )
                      }
                    />
                  )}
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Actions this console cannot take</CardTitle>
              <CardDescription>
                Corrections that need a server routine this domain does not have.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-5">
            <UnavailableAction
              label="Bulk-fix balances against voucher expectations"
              icon={<Wallet />}
              reason="The bulk-fix-balances function expects a per-user list of expected-versus-actual amounts, and that comparison is produced by the balance-audit pipeline, which this domain does not read. Sending it a list this console computed would mean the browser choosing the balances — exactly the write this rebuild removed. TODO(server): expose the audit comparison as a server routine so the correction can be requested by user id alone."
            />
            <UnavailableAction
              label="Write off an unbacked position to zero"
              icon={<Scale />}
              reason="admin_correct_unbacked_positions scales to the admin-credited value, so an account with no credit is already scaled to zero by the normal correction. There is no separate write-off routine, and no client-side path to one. TODO(server): only if a policy ever needs a write-off that differs from the credited value."
            />
            <UnavailableAction
              label="Undo a revert"
              icon={<Undo2 />}
              reason="admin_revert_position_correction restores the pre-correction values but does not record a new before-state, so a revert cannot itself be reverted. Re-running the correction from the table above achieves the same result and is audited. TODO(server): have the revert write its own before_data."
            />
          </CardContent>
        </Card>
      </div>
    </>
  );
}
