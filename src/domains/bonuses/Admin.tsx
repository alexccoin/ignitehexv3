import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { AlertTriangle, Check, History, PlayCircle, RefreshCw, X } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { relativeTime, shortDate } from '@/lib/format';
import {
  useAdminAirdrops,
  useAdminCorrections,
  useAdminVouchers,
  useCorrectVoucherAmount,
  useCorrectVoucherTokens,
  useReviewVoucher,
  useSetAirdropStatus,
  useVoucherErrors,
  useVoucherHistory,
  useVoucherSweep,
  type AdminVoucherRow,
  type SweepJob,
} from './hooks';
import { useSafeMode, useSafeModeAutoEngage } from './safeMode';
import { Async, Detail, LockedAction, Pills, SafeModeGate, Section, amountLabel } from './shared';

/**
 * Voucher review, the correction queue and the airdrop queue.
 *
 * Everything that would put tokens on a member's balance sits behind SAFE MODE,
 * which is engaged by default, re-engages fifteen minutes after release, and
 * re-engages again when this screen unmounts. The gate is enforced inside the
 * mutations, not by the disabled attribute — a disabled button is a hint, and
 * v2's admin surfaces were a sequence of hints in front of unguarded writes.
 *
 * The one thing this screen will not do is credit an airdrop. v2 did that here
 * by reading `user_wallets.arss_balance`, adding the amount in JavaScript and
 * writing the sum back to both `arss_balance` and `total_earned` — so two
 * approvals in the same second lost one, and the second credit to any account
 * overwrote the lifetime total with the current balance. There is no
 * server-side function for it yet, so the control is disabled and says why.
 */
export default function Admin() {
  useSafeModeAutoEngage();

  return (
    <>
      <PageHeader
        title="Rewards review"
        description="Voucher review, restatements and the airdrop queue."
      />

      <div className="space-y-6">
        <SafeModeGate />
        <VoucherQueue />
        <CorrectionQueue />
        <SweepPanel />
        <ErrorLog />
        <AirdropQueue />
      </div>
    </>
  );
}

/* ================================================================ vouchers */

const VOUCHER_STATUSES = ['pending', 'approved', 'rejected', 'all'] as const;

function VoucherQueue() {
  const [status, setStatus] = useState<string>('pending');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const vouchers = useAdminVouchers(status);
  const review = useReviewVoucher();
  const { blocked } = useSafeMode();

  const selected = (vouchers.data ?? []).find((v) => v.id === selectedId) ?? null;

  async function decide(voucher: AdminVoucherRow, next: string) {
    try {
      await review.mutateAsync({ voucherId: voucher.id, status: next });
      toast.success(`Voucher moved to ${next}.`);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The decision was not applied.');
    }
  }

  return (
    <>
      <Section
        title="Voucher review"
        description="Approving releases tokens through process_voucher_redemption_with_audit, which does the status change, the credit and the audit entry in one call."
        actions={<Pills options={VOUCHER_STATUSES} value={status} onChange={setStatus} label="Status" />}
        bodyClassName="p-0 pt-0"
      >
        <Async
          query={vouchers}
          isEmpty={(d) => d.length === 0}
          emptyTitle="Queue is clear"
          emptyDescription={`No vouchers with status "${status}".`}
          skeleton={
            <div className="p-5">
              <Skeleton className="h-40 w-full" />
            </div>
          }
        >
          {(rows) => (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Claimant</TH>
                    <TH>Package</TH>
                    <TH>Token</TH>
                    <TH className="text-right">Credited</TH>
                    <TH>Raised</TH>
                    <TH>Status</TH>
                    <TH className="text-right">Decision</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((v) => {
                    const busy = review.isPending;
                    return (
                      <TR key={v.id}>
                        <TD className="max-w-48 truncate font-medium">{v.full_name}</TD>
                        {/* Verbatim — this string is the correction jobs' key. */}
                        <TD className="max-w-72 truncate" title={v.package_type}>
                          {v.package_type}
                        </TD>
                        <TD className="uppercase text-muted-foreground">{v.token_type}</TD>
                        <TD className="tabular text-right">
                          {v.tokens_credited === true
                            ? amountLabel(v.token_type.toLowerCase(), Number(v.credited_amount ?? 0))
                            : '—'}
                        </TD>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {relativeTime(v.created_at)}
                        </TD>
                        <TD>
                          <StatusBadge status={v.status} />
                        </TD>
                        <TD>
                          <div className="flex items-center justify-end gap-1.5">
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label={`Open ${v.full_name}'s voucher`}
                              onClick={() => setSelectedId(v.id === selectedId ? null : v.id)}
                            >
                              <History aria-hidden="true" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label={`Reject ${v.full_name}'s voucher`}
                              disabled={busy || v.status === 'rejected'}
                              onClick={() => void decide(v, 'rejected')}
                            >
                              <X aria-hidden="true" />
                            </Button>
                            {/*
                              Safe mode: approving is the crediting branch, so it
                              is unavailable until the phrase has been typed. The
                              mutation refuses too — this is the visible half.
                            */}
                            <Button
                              variant="primary"
                              size="icon"
                              aria-label={
                                blocked
                                  ? 'Approving is blocked while safe mode is on'
                                  : `Approve ${v.full_name}'s voucher and credit the tokens`
                              }
                              title={blocked ? 'Safe mode is on' : undefined}
                              disabled={busy || blocked || v.status === 'approved'}
                              onClick={() => void decide(v, 'approved')}
                            >
                              <Check aria-hidden="true" />
                            </Button>
                          </div>
                        </TD>
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Async>
      </Section>

      {selected && <VoucherDetail voucher={selected} onClose={() => setSelectedId(null)} />}
    </>
  );
}

/* ------------------------------------------------------------------------ */

function VoucherDetail({ voucher, onClose }: { voucher: AdminVoucherRow; onClose: () => void }) {
  const history = useVoucherHistory(voucher.id);
  const recompute = useCorrectVoucherTokens();
  const restate = useCorrectVoucherAmount();
  const { blocked } = useSafeMode();

  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');

  const amountValue = Number(amount);
  const amountValid = amount.trim().length > 0 && Number.isFinite(amountValue) && amountValue >= 0;
  const canRestate = amountValid && reason.trim().length > 3 && !blocked && !restate.isPending;

  async function onRecompute() {
    try {
      await recompute.mutateAsync(voucher.id);
      toast.success('Token amount recomputed from the server package table.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The recompute did not run.');
    }
  }

  async function onRestate(event: FormEvent) {
    event.preventDefault();
    if (!canRestate) return;
    try {
      await restate.mutateAsync({
        voucherId: voucher.id,
        amount: amountValue,
        reason: reason.trim(),
      });
      toast.success('Voucher amount restated.');
      setAmount('');
      setReason('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The restatement did not run.');
    }
  }

  return (
    <Section
      title={`Voucher — ${voucher.full_name}`}
      description="Corrections run server-side. Nothing on this panel computes a balance."
      actions={
        <Button variant="ghost" size="icon" aria-label="Close voucher detail" onClick={onClose}>
          <X aria-hidden="true" />
        </Button>
      }
      bodyClassName="space-y-6 p-5"
    >
      <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
        <Detail label="Package" value={<span className="break-all">{voucher.package_type}</span>} />
        <Detail label="Token" value={voucher.token_type.toUpperCase()} />
        <Detail label="Paid by" value={voucher.payment_type} />
        <Detail
          label="Credited"
          value={
            voucher.tokens_credited === true
              ? amountLabel(voucher.token_type.toLowerCase(), Number(voucher.credited_amount ?? 0))
              : 'Not credited'
          }
        />
        <Detail
          label="Payment reference"
          value={
            <span className="break-all font-mono text-xs">
              {voucher.payment_hash ?? voucher.confirmation_number ?? '—'}
            </span>
          }
        />
        <Detail label="Stated amount" value={voucher.amount ?? '—'} />
        <Detail label="Raised" value={shortDate(voucher.created_at)} />
        <Detail label="Status" value={<StatusBadge status={voucher.status} />} />
      </div>

      {voucher.admin_notes && (
        <p className="rounded-md bg-elevated p-3 text-sm text-muted-foreground">
          {voucher.admin_notes}
        </p>
      )}

      <div className="space-y-3 border-t border-border pt-5">
        <p className="text-sm font-medium">Corrections</p>

        {blocked ? (
          <LockedAction
            label="Recompute from package table"
            reason="Safe mode is on. Recomputing writes a new credited amount, so it is blocked until the release phrase is typed above."
          />
        ) : (
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="secondary" size="sm" disabled={recompute.isPending} onClick={() => void onRecompute()}>
              <RefreshCw aria-hidden="true" />
              {recompute.isPending ? 'Recomputing…' : 'Recompute from package table'}
            </Button>
            <p className="flex-1 text-xs text-muted-foreground">
              Runs admin_correct_voucher_tokens, which reads the package label off the row and
              restates the credit from the server's own table.
            </p>
          </div>
        )}

        <form className="grid gap-3 sm:grid-cols-[minmax(0,12rem)_1fr_auto]" onSubmit={onRestate}>
          <Field
            label="Corrected amount"
            htmlFor="vc-amount"
            error={amount.trim().length > 0 && !amountValid ? 'Enter zero or more.' : undefined}
          >
            <Input
              id="vc-amount"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              disabled={blocked}
            />
          </Field>
          <Field
            label="Reason"
            htmlFor="vc-reason"
            hint="Recorded on voucher_corrections against your user id."
          >
            <Input
              id="vc-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              disabled={blocked}
            />
          </Field>
          <div className="flex items-end">
            <Button type="submit" variant="danger" disabled={!canRestate}>
              {restate.isPending ? 'Restating…' : 'Restate'}
            </Button>
          </div>
        </form>
        {blocked && (
          <p className="text-xs text-muted-foreground">
            Restating is blocked while safe mode is on.
          </p>
        )}
      </div>

      <div className="space-y-3 border-t border-border pt-5">
        <p className="text-sm font-medium">Audit trail</p>
        <Async
          query={history}
          isEmpty={(d) => d.length === 0}
          emptyTitle="No recorded actions"
          emptyDescription="Nothing has been done to this voucher yet."
          skeleton={<Skeleton className="h-20 w-full" />}
        >
          {(rows) => (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>When</TH>
                    <TH>Action</TH>
                    <TH>From</TH>
                    <TH>To</TH>
                    <TH>Notes</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((h) => (
                    <TR key={h.id}>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(h.created_at)}
                      </TD>
                      <TD>{h.action_performed}</TD>
                      <TD className="text-muted-foreground">{h.status_from ?? '—'}</TD>
                      <TD>
                        <StatusBadge status={h.status_to} />
                      </TD>
                      <TD className="max-w-64 truncate text-muted-foreground">
                        {h.admin_notes ?? '—'}
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Async>
      </div>
    </Section>
  );
}

/* ============================================================= corrections */

function CorrectionQueue() {
  const corrections = useAdminCorrections();

  const applied = corrections.data ?? [];
  // Deliberately a count, not a net total. These rows restate STR, CCOS and
  // ARSS amounts, and adding those together produces a number that means
  // nothing — the mistake v2 made every time it summed a mixed-token column.
  const increases = applied.filter((c) => Number(c.difference ?? 0) >= 0).length;

  return (
    <Section
      title="Correction queue"
      description="Every restatement applied. Counts rather than a total: these rows are in different tokens."
      actions={
        <div className="flex gap-2">
          <Badge tone="success">{increases} increased</Badge>
          <Badge tone="danger">{applied.length - increases} reduced</Badge>
        </div>
      }
      bodyClassName="p-0 pt-0"
    >
      <Async
        query={corrections}
        isEmpty={(d) => d.length === 0}
        emptyTitle="No corrections"
        emptyDescription="No voucher has been restated."
        skeleton={
          <div className="p-5">
            <Skeleton className="h-32 w-full" />
          </div>
        }
      >
        {(rows) => (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>Member</TH>
                  <TH>Package</TH>
                  <TH className="text-right">Was</TH>
                  <TH className="text-right">Now</TH>
                  <TH className="text-right">Difference</TH>
                  <TH>Type</TH>
                  <TH>When</TH>
                </TR>
              </THead>
              <TBody>
                {rows.map((c) => {
                  const symbol = c.token_type.toLowerCase();
                  const diff = Number(c.difference ?? 0);
                  return (
                    <TR key={c.id}>
                      <TD className="max-w-40 truncate font-medium">{c.full_name}</TD>
                      <TD className="max-w-64 truncate" title={c.package_type}>
                        {c.package_type}
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {amountLabel(symbol, Number(c.previous_amount))}
                      </TD>
                      <TD className="tabular text-right">
                        {amountLabel(symbol, Number(c.corrected_amount))}
                      </TD>
                      <TD className="text-right">
                        <Badge tone={diff >= 0 ? 'success' : 'danger'}>
                          {diff >= 0 ? '+' : '−'}
                          {amountLabel(symbol, Math.abs(diff))}
                        </Badge>
                      </TD>
                      <TD className="text-muted-foreground">{c.correction_type}</TD>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(c.corrected_at)}
                      </TD>
                    </TR>
                  );
                })}
              </TBody>
            </Table>
          </TableWrap>
        )}
      </Async>
    </Section>
  );
}

/* ================================================================= sweeps */

function SweepPanel() {
  return (
    <Section
      title="Bulk repair"
      description="Both jobs run under the service role inside the edge function, which re-checks your role before it touches anything."
      bodyClassName="space-y-5 p-5"
    >
      <SweepJobRow
        job="correct-precex-vouchers"
        title="Pre-CEX STR vouchers"
        body="Scans approved, credited pre-CEX STR vouchers and restates any whose credit does not match the fixed allocation for their package label."
        supportsDryRun
      />
      <SweepJobRow
        job="correct-str-vouchers-targeted"
        title="Targeted STR voucher list"
        body="Applies a fixed list of voucher ids compiled by hand. There is no dry run, so it is always treated as a crediting action."
        supportsDryRun={false}
      />
    </Section>
  );
}

function SweepJobRow({
  job,
  title,
  body,
  supportsDryRun,
}: {
  job: SweepJob;
  title: string;
  body: string;
  supportsDryRun: boolean;
}) {
  const sweep = useVoucherSweep();
  const { blocked } = useSafeMode();
  const [result, setResult] = useState<string | null>(null);

  async function run(dryRun: boolean) {
    setResult(null);
    try {
      const data = await sweep.mutateAsync({ job, dryRun });
      const scanned = data.total_scanned ?? 0;
      const changes = data.total_corrections ?? 0;
      setResult(
        dryRun
          ? `Dry run: ${scanned} scanned, ${changes} would be corrected.`
          : `Applied: ${scanned} scanned, ${changes} corrected.`
      );
      toast.success(dryRun ? 'Dry run complete.' : 'Sweep applied.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The job did not run.');
    }
  }

  return (
    <div className="space-y-3 rounded-md border border-border p-4">
      <div>
        <p className="text-sm font-medium">{title}</p>
        <p className="text-xs text-muted-foreground">{body}</p>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        {supportsDryRun && (
          <Button
            variant="secondary"
            size="sm"
            disabled={sweep.isPending}
            onClick={() => void run(true)}
          >
            <PlayCircle aria-hidden="true" />
            Dry run
          </Button>
        )}
        {blocked ? (
          <LockedAction
            label="Apply"
            reason="Safe mode is on. Applying this sweep writes new credited amounts, so it is blocked until the release phrase is typed above."
          />
        ) : (
          <Button variant="danger" size="sm" disabled={sweep.isPending} onClick={() => void run(false)}>
            {sweep.isPending ? 'Running…' : 'Apply'}
          </Button>
        )}
      </div>

      {result && <p className="tabular text-xs text-muted-foreground">{result}</p>}
    </div>
  );
}

/* ============================================================== error log */

function ErrorLog() {
  const errors = useVoucherErrors();

  return (
    <Section
      title="Pipeline failures"
      description="What the voucher pipeline recorded when something went wrong."
      bodyClassName="p-0 pt-0"
    >
      <Async
        query={errors}
        isEmpty={(d) => d.length === 0}
        emptyTitle="No recorded failures"
        emptyDescription="The voucher pipeline has not logged an error."
        skeleton={
          <div className="p-5">
            <Skeleton className="h-24 w-full" />
          </div>
        }
      >
        {(rows) => (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>When</TH>
                  <TH>Type</TH>
                  <TH>Message</TH>
                  <TH>Voucher</TH>
                </TR>
              </THead>
              <TBody>
                {rows.map((e) => (
                  <TR key={e.id}>
                    <TD className="whitespace-nowrap text-muted-foreground">
                      {shortDate(e.created_at)}
                    </TD>
                    <TD>
                      <Badge tone="danger">{e.error_type}</Badge>
                    </TD>
                    <TD className="max-w-96 truncate" title={e.error_message}>
                      {e.error_message}
                    </TD>
                    <TD className="font-mono text-xs text-muted-foreground">
                      {e.voucher_redemption_id?.slice(0, 8) ?? '—'}
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          </TableWrap>
        )}
      </Async>
    </Section>
  );
}

/* ================================================================ airdrop */

const AIRDROP_STATUSES = ['pending', 'approved', 'rejected', 'all'] as const;

function AirdropQueue() {
  const [status, setStatus] = useState<string>('pending');
  const airdrops = useAdminAirdrops(status);
  const setAirdropStatus = useSetAirdropStatus();

  const pending = (airdrops.data ?? []).filter((r) => r.status === 'pending').length;

  async function decline(id: string, name: string) {
    try {
      await setAirdropStatus.mutateAsync({ id, status: 'rejected' });
      toast.success(`${name}'s registration was declined.`);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The decision was not applied.');
    }
  }

  return (
    <Section
      title="Airdrop queue"
      description="Registrations awaiting a decision."
      actions={<Pills options={AIRDROP_STATUSES} value={status} onChange={setStatus} label="Status" />}
      bodyClassName="space-y-5 p-5"
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Stat
          label="Awaiting decision"
          value={String(pending)}
          loading={airdrops.isLoading}
          tone={pending > 0 ? 'warning' : 'default'}
          icon={<AlertTriangle className="size-4" aria-hidden="true" />}
        />
        <div className="panel space-y-3 p-5">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Crediting
          </p>
          {/*
            TODO(server): an `approve_airdrop_registration(p_registration_id uuid,
            p_amount numeric)` SECURITY DEFINER function that, in one statement,
            sets status/tokens_credited/credited_amount/credited_at on the
            registration AND credits user_wallets by adding to arss_balance and
            adding to total_earned — accumulating both, never assigning either
            from the other.

            Until that exists this cannot be done from the browser. v2 did it
            here with SELECT arss_balance → add in JS → UPDATE, and set
            total_earned = arss_balance + amount, so a member's second airdrop
            replaced their lifetime total with their current balance and two
            concurrent approvals lost one credit outright.
          */}
          <LockedAction
            label="Approve and credit"
            reason="No server-side function releases airdrop tokens yet. Crediting from the browser would mean reading a balance, adding to it and writing it back — the exact pattern that lost credits and corrupted total_earned in v2."
          />
        </div>
      </div>

      <Async
        query={airdrops}
        isEmpty={(d) => d.length === 0}
        emptyTitle="Queue is clear"
        emptyDescription={`No registrations with status "${status}".`}
        skeleton={<Skeleton className="h-32 w-full" />}
      >
        {(rows) => (
          <TableWrap>
            <Table>
              <THead>
                <TR>
                  <TH>Member</TH>
                  <TH>Event</TH>
                  <TH className="text-right">Requested</TH>
                  <TH className="text-right">Credited</TH>
                  <TH>Raised</TH>
                  <TH>Status</TH>
                  <TH className="text-right">Decision</TH>
                </TR>
              </THead>
              <TBody>
                {rows.map((r) => (
                  <TR key={r.id}>
                    <TD className="max-w-48 truncate font-medium">{r.full_name}</TD>
                    <TD className="uppercase text-muted-foreground">{r.event_type ?? '—'}</TD>
                    <TD className="tabular text-right text-muted-foreground">
                      {amountLabel('arss', Number(r.requested_amount))}
                    </TD>
                    <TD className="tabular text-right">
                      {r.tokens_credited === true
                        ? amountLabel('arss', Number(r.credited_amount ?? 0))
                        : '—'}
                    </TD>
                    <TD className="whitespace-nowrap text-muted-foreground">
                      {relativeTime(r.created_at)}
                    </TD>
                    <TD>
                      <StatusBadge status={r.status} />
                    </TD>
                    <TD className="text-right">
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={`Decline ${r.full_name}'s registration`}
                        disabled={setAirdropStatus.isPending || r.status === 'rejected'}
                        onClick={() => void decline(r.id, r.full_name)}
                      >
                        <X aria-hidden="true" />
                      </Button>
                    </TD>
                  </TR>
                ))}
              </TBody>
            </Table>
          </TableWrap>
        )}
      </Async>
    </Section>
  );
}
