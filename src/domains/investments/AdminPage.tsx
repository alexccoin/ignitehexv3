import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { PlayCircle, RefreshCw, ServerCog } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { STR_REFERENCE_PRICE } from './constants';
import { Async, FilterPills, LockedAction, Section } from './shared';
import {
  useAdminAirdrop,
  useAdminPrivateApplications,
  useAdminSeedApplications,
  useAdminStarwNodes,
  useAdminVouchers,
  useAssignStarwNodes,
  useCorrectVoucherAmount,
  useCorrectVoucherTokens,
  useReviewVoucher,
  useSeedStrAdminAccess,
  useVoucherSweep,
} from './hooks';

/**
 * The review queues.
 *
 * The route is guarded on `admin`, but the guard is only there to keep the
 * console out of the way of people who cannot use it. Each action below is
 * a single server-side call that re-checks the caller itself, because a UI
 * guard is not an authorisation boundary.
 *
 * Queues whose decisions credit tokens are read-only here: v2's admin screens
 * approved an application by selecting a balance, adding the award in
 * JavaScript and writing the sum back, across five different files. Until v3
 * has a review function that does it in one statement, the decision buttons
 * stay disabled rather than reintroducing the lost-update bug.
 */

const QUEUES = ['vouchers', 'seed', 'private_seed', 'airdrop', 'nodes'] as const;
type Queue = (typeof QUEUES)[number];

const QUEUE_LABELS: Record<Queue, string> = {
  vouchers: 'Vouchers',
  seed: 'Seed applications',
  private_seed: 'Private seed',
  airdrop: 'Airdrop',
  nodes: 'StarW nodes',
};

export default function AdminPage() {
  const [queue, setQueue] = useState<Queue>('vouchers');
  const seedAdmin = useSeedStrAdminAccess();

  return (
    <>
      <PageHeader
        title="Investment review"
        description="Approve what the server can settle in one statement, and nothing else."
      />

      <div className="mb-4 flex flex-wrap gap-2" role="tablist" aria-label="Review queues">
        {QUEUES.map((q) => (
          <button
            key={q}
            role="tab"
            type="button"
            aria-selected={queue === q}
            onClick={() => setQueue(q)}
            className={cn(
              'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
              queue === q
                ? 'bg-primary/10 text-primary ring-primary/20'
                : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
            )}
          >
            {QUEUE_LABELS[q]}
          </button>
        ))}
      </div>

      {queue === 'vouchers' && <VoucherQueue />}
      {queue === 'seed' && <SeedQueue canReview={seedAdmin.data === true} />}
      {queue === 'private_seed' && <PrivateSeedQueue canReview={seedAdmin.data === true} />}
      {queue === 'airdrop' && <AirdropQueue />}
      {queue === 'nodes' && <NodesQueue />}
    </>
  );
}

/* -------------------------------------------------------------- vouchers */

const VOUCHER_FILTERS = ['pending', 'approved', 'rejected', 'all'] as const;

function VoucherQueue() {
  const [filter, setFilter] = useState<string>('pending');
  const vouchers = useAdminVouchers(filter);
  const review = useReviewVoucher();
  const correctTokens = useCorrectVoucherTokens();
  const correctAmount = useCorrectVoucherAmount();

  const [amounts, setAmounts] = useState<Record<string, string>>({});

  async function decide(voucherId: string, status: string) {
    try {
      await review.mutateAsync({ voucherId, status });
      toast.success(status === 'approved' ? 'Voucher approved.' : 'Voucher rejected.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not update the voucher');
    }
  }

  async function recompute(voucherId: string) {
    try {
      await correctTokens.mutateAsync(voucherId);
      toast.success('Token amount recomputed from the package table.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not recompute the amount');
    }
  }

  async function restate(voucherId: string) {
    const raw = amounts[voucherId];
    const value = Number(raw);
    if (!raw || !Number.isFinite(value) || value < 0) {
      toast.error('Enter a valid corrected amount.');
      return;
    }
    try {
      await correctAmount.mutateAsync({
        voucherId,
        amount: value,
        reason: 'Manual correction from the review queue',
      });
      toast.success('Amount restated.');
      setAmounts((m) => ({ ...m, [voucherId]: '' }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not restate the amount');
    }
  }

  const busy = review.isPending || correctTokens.isPending || correctAmount.isPending;

  return (
    <div className="space-y-6">
      <Section
        title="Voucher claims"
        description="Approving credits the member in the same database call that records the audit entry."
        actions={
          <FilterPills
            options={VOUCHER_FILTERS}
            value={filter}
            onChange={setFilter}
            label="Filter vouchers by status"
          />
        }
        bodyClassName="p-0 pt-0"
      >
        <Async
          query={vouchers}
          isEmpty={(rows) => rows.length === 0}
          emptyTitle="Queue is clear"
          emptyDescription="No vouchers match this filter."
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
                    <TH>Member</TH>
                    <TH>Package</TH>
                    <TH>Token</TH>
                    <TH className="text-right">Credited</TH>
                    <TH>Restate</TH>
                    <TH>Claimed</TH>
                    <TH>Status</TH>
                    <TH className="text-right">Decision</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((v) => {
                    const settled = v.status !== 'pending';
                    return (
                      <TR key={v.id}>
                        <TD>
                          <p className="font-medium">{v.full_name}</p>
                          <p className="text-xs text-muted-foreground">{v.email_address}</p>
                        </TD>
                        <TD className="max-w-56 truncate">{v.package_type}</TD>
                        <TD className="uppercase text-muted-foreground">{v.token_type}</TD>
                        <TD className="tabular text-right">
                          {v.tokens_credited ? (
                            Number(v.credited_amount ?? 0).toLocaleString('en-IE')
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </TD>
                        <TD>
                          <div className="flex items-center gap-2">
                            <Input
                              type="number"
                              min="0"
                              step="any"
                              className="h-8 w-28"
                              value={amounts[v.id] ?? ''}
                              onChange={(e) =>
                                setAmounts((m) => ({ ...m, [v.id]: e.target.value }))
                              }
                              aria-label={`Corrected amount for ${v.package_type}`}
                            />
                            <Button
                              size="sm"
                              variant="ghost"
                              disabled={busy || !amounts[v.id]}
                              onClick={() => void restate(v.id)}
                            >
                              Set
                            </Button>
                            <Button
                              size="icon"
                              variant="ghost"
                              className="size-8"
                              disabled={busy}
                              onClick={() => void recompute(v.id)}
                              aria-label={`Recompute token amount for ${v.package_type}`}
                            >
                              <RefreshCw aria-hidden="true" />
                            </Button>
                          </div>
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(v.created_at)}</TD>
                        <TD>
                          <StatusBadge status={v.status} />
                        </TD>
                        <TD>
                          <div className="flex justify-end gap-2">
                            <Button
                              size="sm"
                              variant="secondary"
                              disabled={settled || busy}
                              onClick={() => void decide(v.id, 'approved')}
                            >
                              Approve
                            </Button>
                            <Button
                              size="sm"
                              variant="ghost"
                              disabled={settled || busy}
                              onClick={() => void decide(v.id, 'rejected')}
                            >
                              Reject
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

      <SweepSection />
    </div>
  );
}

function SweepSection() {
  return (
    <Section
      title="Bulk corrections"
      description="Repair jobs that re-derive credited amounts from the package table."
    >
      <SweepRunner
        job="correct-precex-vouchers"
        title="Pre-CEX STR vouchers"
        description="Re-derives every approved pre-CEX STR voucher from its package. Supports a dry run."
        supportsDryRun
      />
      <div className="mt-4 border-t border-border pt-4">
        <SweepRunner
          job="correct-str-vouchers-targeted"
          title="Targeted STR vouchers"
          description="Applies the fixed correction list. This job has no dry run and applies immediately."
          supportsDryRun={false}
        />
      </div>
    </Section>
  );
}

function SweepRunner({
  job,
  title,
  description,
  supportsDryRun,
}: {
  job: 'correct-precex-vouchers' | 'correct-str-vouchers-targeted';
  title: string;
  description: string;
  supportsDryRun: boolean;
}) {
  const [dryRun, setDryRun] = useState(true);
  const [result, setResult] = useState<string | null>(null);
  const sweep = useVoucherSweep();

  async function run() {
    setResult(null);
    try {
      const data = await sweep.mutateAsync({ job, dryRun: supportsDryRun ? dryRun : false });
      const scanned = data.total_scanned ?? 0;
      const corrections = data.total_corrections ?? 0;
      setResult(
        `${data.dryRun ? 'Dry run' : 'Applied'}: ${corrections} correction${
          corrections === 1 ? '' : 's'
        } from ${scanned} scanned.`
      );
      toast.success('Sweep finished.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'The sweep failed');
    }
  }

  return (
    <div className="space-y-3">
      <div>
        <p className="text-sm font-medium">{title}</p>
        <p className="text-xs text-muted-foreground">{description}</p>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        {supportsDryRun && (
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={dryRun}
              onChange={(e) => setDryRun(e.target.checked)}
              className="size-4 rounded border-input"
            />
            Dry run
          </label>
        )}
        <Button size="sm" variant="secondary" disabled={sweep.isPending} onClick={() => void run()}>
          <PlayCircle aria-hidden="true" />
          {sweep.isPending ? 'Running…' : 'Run'}
        </Button>
        {result && <Badge tone="info">{result}</Badge>}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------ seed queues */

const APPLICATION_FILTERS = ['pending', 'approved', 'suspended', 'declined', 'all'] as const;

/** The decision path both seed queues are waiting on. */
const APPLICATION_REVIEW_BLOCKED =
  'Approving an application credits shares and STR. That has to happen in one server-side statement, together with the audit entry, before it can be offered here.';

function SeedQueue({ canReview }: { canReview: boolean }) {
  const [filter, setFilter] = useState<string>('pending');
  const applications = useAdminSeedApplications(filter);

  return (
    <Section
      title="Seed applications"
      description={
        canReview
          ? 'You hold seed-round review rights.'
          : 'Read-only: your account does not hold seed-round review rights.'
      }
      actions={
        <FilterPills
          options={APPLICATION_FILTERS}
          value={filter}
          onChange={setFilter}
          label="Filter applications by status"
        />
      }
      bodyClassName="p-0 pt-0"
    >
      <Async
        query={applications}
        isEmpty={(rows) => rows.length === 0}
        emptyTitle="Queue is clear"
        emptyDescription="No applications match this filter."
        skeleton={
          <div className="p-5">
            <Skeleton className="h-40 w-full" />
          </div>
        }
      >
        {(rows) => (
          <>
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Applicant</TH>
                    <TH>Tier</TH>
                    <TH className="text-right">Commitment</TH>
                    <TH className="text-right">Shares</TH>
                    <TH className="text-right">Credited</TH>
                    <TH>Payment</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((a) => (
                    <TR key={a.id}>
                      <TD>
                        <p className="font-medium">{a.full_name}</p>
                        <p className="text-xs text-muted-foreground">{a.email}</p>
                      </TD>
                      <TD className="text-muted-foreground">{a.investment_tier}</TD>
                      <TD className="tabular text-right">
                        {money(Number(a.investment_amount ?? 0) * STR_REFERENCE_PRICE, 'USD')}
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {Number(a.expected_return_rate ?? 0).toLocaleString('en-IE')}
                      </TD>
                      <TD className="tabular text-right">
                        {a.str_shares_credited
                          ? Number(a.str_shares_credited).toLocaleString('en-IE')
                          : '—'}
                      </TD>
                      <TD>
                        {a.payment_status ? (
                          <StatusBadge status={a.payment_status} />
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TD>
                      <TD>
                        <StatusBadge status={a.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>

            {/* TODO(server): needs a review-seed-str-application RPC taking
                (application_id, decision, notes) that flips the status, credits
                user_str_shares with a relative update and writes
                seed_str_audit_log — all in one transaction. */}
            <div className="border-t border-border p-5">
              <LockedAction label="Approve / decline" reason={APPLICATION_REVIEW_BLOCKED} />
            </div>
          </>
        )}
      </Async>
    </Section>
  );
}

function PrivateSeedQueue({ canReview }: { canReview: boolean }) {
  const [filter, setFilter] = useState<string>('pending');
  const applications = useAdminPrivateApplications(filter);

  return (
    <Section
      title="Private seed applications"
      description={
        canReview
          ? 'You hold seed-round review rights.'
          : 'Read-only: your account does not hold seed-round review rights.'
      }
      actions={
        <FilterPills
          options={APPLICATION_FILTERS}
          value={filter}
          onChange={setFilter}
          label="Filter private applications by status"
        />
      }
      bodyClassName="p-0 pt-0"
    >
      <Async
        query={applications}
        isEmpty={(rows) => rows.length === 0}
        emptyTitle="Queue is clear"
        emptyDescription="No applications match this filter."
        skeleton={
          <div className="p-5">
            <Skeleton className="h-40 w-full" />
          </div>
        }
      >
        {(rows) => (
          <>
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Applicant</TH>
                    <TH>Tier</TH>
                    <TH className="text-right">Commitment</TH>
                    <TH className="text-right">Credited</TH>
                    <TH>Payment</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((a) => (
                    <TR key={a.id}>
                      <TD>
                        <p className="font-medium">{a.full_name}</p>
                        <p className="text-xs text-muted-foreground">{a.email}</p>
                      </TD>
                      <TD className="text-muted-foreground">{a.investment_tier ?? '—'}</TD>
                      <TD className="tabular text-right">
                        {money(Number(a.investment_amount ?? 0) * STR_REFERENCE_PRICE, 'USD')}
                      </TD>
                      <TD className="tabular text-right">
                        {a.str_shares_credited
                          ? Number(a.str_shares_credited).toLocaleString('en-IE')
                          : '—'}
                      </TD>
                      <TD>
                        {a.payment_status ? (
                          <StatusBadge status={a.payment_status} />
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TD>
                      <TD>
                        <StatusBadge status={a.status ?? 'pending'} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>

            {/* TODO(server): same review-private-seed-str-application function as
                the open round, writing private_seed_str_audit_log. */}
            <div className="border-t border-border p-5">
              <LockedAction label="Approve / decline" reason={APPLICATION_REVIEW_BLOCKED} />
            </div>
          </>
        )}
      </Async>
    </Section>
  );
}

/* --------------------------------------------------------------- airdrop */

const AIRDROP_FILTERS = ['pending', 'approved', 'rejected', 'all'] as const;

function AirdropQueue() {
  const [filter, setFilter] = useState<string>('pending');
  const registrations = useAdminAirdrop(filter);

  return (
    <Section
      title="Airdrop registrations"
      actions={
        <FilterPills
          options={AIRDROP_FILTERS}
          value={filter}
          onChange={setFilter}
          label="Filter registrations by status"
        />
      }
      bodyClassName="p-0 pt-0"
    >
      <Async
        query={registrations}
        isEmpty={(rows) => rows.length === 0}
        emptyTitle="Queue is clear"
        emptyDescription="No registrations match this filter."
        skeleton={
          <div className="p-5">
            <Skeleton className="h-40 w-full" />
          </div>
        }
      >
        {(rows) => (
          <>
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Member</TH>
                    <TH>Event</TH>
                    <TH>Wallet</TH>
                    <TH className="text-right">Requested</TH>
                    <TH className="text-right">Credited</TH>
                    <TH>Registered</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((r) => (
                    <TR key={r.id}>
                      <TD>
                        <p className="font-medium">{r.full_name}</p>
                        <p className="text-xs text-muted-foreground">{r.email_address}</p>
                      </TD>
                      <TD className="uppercase text-muted-foreground">
                        {r.event_type ?? '—'}
                        {r.voucher_type && (
                          <Badge tone="neutral" className="ml-2">
                            {r.voucher_type}
                          </Badge>
                        )}
                      </TD>
                      <TD className="tabular max-w-40 truncate text-xs text-muted-foreground">
                        {r.wallet_address}
                      </TD>
                      <TD className="tabular text-right">
                        {Number(r.requested_amount).toLocaleString('en-IE')}
                      </TD>
                      <TD className="tabular text-right">
                        {r.tokens_credited
                          ? Number(r.credited_amount ?? 0).toLocaleString('en-IE')
                          : '—'}
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(r.created_at)}</TD>
                      <TD>
                        <StatusBadge status={r.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>

            {/* TODO(server): needs a credit-airdrop-registration function that
                sets status, credited_amount and tokens_credited together with
                the wallet credit. v2 credited the wallet from the browser and
                set total_earned from the balance column rather than from the
                previous total, so a second credit overwrote the first. */}
            <div className="border-t border-border p-5">
              <LockedAction
                label="Approve and credit"
                reason="Crediting an airdrop moves tokens, so the decision and the credit have to be one server-side statement."
              />
            </div>
          </>
        )}
      </Async>
    </Section>
  );
}

/* ----------------------------------------------------------------- nodes */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function NodesQueue() {
  const nodes = useAdminStarwNodes();
  const assign = useAssignStarwNodes();

  const [targetUserId, setTargetUserId] = useState('');
  const [nodeCount, setNodeCount] = useState('1');
  const [startNumber, setStartNumber] = useState('1');
  const [workerNodes, setWorkerNodes] = useState('0');
  const [status, setStatus] = useState('active');

  const parsed = {
    count: Number(nodeCount),
    start: Number(startNumber),
    workers: Number(workerNodes),
  };

  const canSubmit =
    UUID.test(targetUserId.trim()) &&
    Number.isInteger(parsed.count) &&
    parsed.count > 0 &&
    Number.isInteger(parsed.start) &&
    parsed.start > 0 &&
    Number.isInteger(parsed.workers) &&
    parsed.workers >= 0 &&
    !assign.isPending;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;

    try {
      await assign.mutateAsync({
        targetUserId: targetUserId.trim(),
        nodeCount: parsed.count,
        startNumber: parsed.start,
        workerNodes: parsed.workers,
        status,
      });
      toast.success(`${parsed.count} node${parsed.count === 1 ? '' : 's'} assigned.`);
      setTargetUserId('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not assign the nodes');
    }
  }

  return (
    <div className="space-y-6">
      <Section
        title="Assign StarW nodes"
        description="Allocation happens in one database call, so two admins cannot hand out the same node number."
      >
        <form className="grid gap-4 md:grid-cols-2 lg:grid-cols-3" onSubmit={submit}>
          <Field
            label="Member user ID"
            htmlFor="n-user"
            hint="The member's auth user id."
            error={
              targetUserId.trim().length > 0 && !UUID.test(targetUserId.trim())
                ? 'That is not a user id.'
                : undefined
            }
          >
            <Input
              id="n-user"
              value={targetUserId}
              onChange={(e) => setTargetUserId(e.target.value)}
              spellCheck={false}
              required
            />
          </Field>

          <Field label="Nodes" htmlFor="n-count">
            <Input
              id="n-count"
              type="number"
              min="1"
              step="1"
              value={nodeCount}
              onChange={(e) => setNodeCount(e.target.value)}
              required
            />
          </Field>

          <Field label="First node number" htmlFor="n-start">
            <Input
              id="n-start"
              type="number"
              min="1"
              step="1"
              value={startNumber}
              onChange={(e) => setStartNumber(e.target.value)}
              required
            />
          </Field>

          <Field label="Worker nodes each" htmlFor="n-workers">
            <Input
              id="n-workers"
              type="number"
              min="0"
              step="1"
              value={workerNodes}
              onChange={(e) => setWorkerNodes(e.target.value)}
              required
            />
          </Field>

          <div className="space-y-1.5">
            <Label htmlFor="n-status">Status</Label>
            <select
              id="n-status"
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm capitalize"
            >
              {['active', 'pending', 'suspended'].map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </div>

          <div className="flex items-end">
            <Button type="submit" disabled={!canSubmit}>
              <ServerCog aria-hidden="true" />
              {assign.isPending ? 'Assigning…' : 'Assign'}
            </Button>
          </div>
        </form>
      </Section>

      <Section title="Assigned nodes" bodyClassName="p-0 pt-0">
        <Async
          query={nodes}
          isEmpty={(rows) => rows.length === 0}
          emptyTitle="No nodes assigned"
          emptyDescription="Nothing has been allocated yet."
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
                    <TH className="text-right">Node</TH>
                    <TH>Holder</TH>
                    <TH className="text-right">Workers</TH>
                    <TH>Assigned</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((n) => (
                    <TR key={n.id}>
                      <TD className="tabular text-right font-medium">#{n.node_number}</TD>
                      <TD>
                        <p className="font-medium">{n.full_name ?? 'Unnamed'}</p>
                        <p className="text-xs text-muted-foreground">{n.email_address}</p>
                      </TD>
                      <TD className="tabular text-right">{n.worker_nodes_count}</TD>
                      <TD className="text-muted-foreground">{shortDate(n.assigned_at)}</TD>
                      <TD>
                        <StatusBadge status={n.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Async>
      </Section>
    </div>
  );
}
