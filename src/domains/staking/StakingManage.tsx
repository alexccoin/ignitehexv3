import { useState } from 'react';
import { toast } from 'sonner';
import { Check, Inbox, Loader2, Pause, Pencil, Play, Plus, ShieldAlert, X } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { compact, percent, shortDate, token as formatToken } from '@/lib/format';
import { Section, Segmented } from './components';
import { PoolTemplateForm } from './PoolTemplateForm';
import { REQUEST_FILTERS, poolTypeLabel, type RequestFilter } from './constants';
import {
  useAdminStakingRequests,
  usePoolTemplates,
  useProcessStakingRequest,
  useRewardDistributions,
  useRunRewardDistribution,
  useSetPoolTemplateStatus,
  type EnhancedPoolRow,
} from './hooks';

/**
 * Pool management and reward distribution.
 *
 * Nothing on this screen writes a balance. Approving a request calls
 * `process_staking_request`, which opens the position, sets `apy_rate` and
 * `dynamic_apy` from the database's own schedule and stamps the request inside
 * one transaction — so an administrator's browser never chooses a rate, and a
 * half-applied approval is not possible. Running a distribution calls the
 * `vesting-rewards-distribution` edge function, which re-checks the caller's
 * admin role with the service role before delegating to
 * `distribute_vested_rewards`.
 *
 * Deliberately absent: v2's `distribute_enhanced_rewards` RPC, which credited
 * `rewards_earned` with no matching debit and was executable by any signed-in
 * user. It is not wrapped by a hook and not reachable from this screen.
 */

const FILTER_OPTIONS = REQUEST_FILTERS.map((value) => ({
  value,
  label: value === 'all' ? 'All' : value.charAt(0).toUpperCase() + value.slice(1),
}));

export default function StakingManage() {
  const [filter, setFilter] = useState<RequestFilter>('pending');
  const [activeId, setActiveId] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  /** null = closed, { pool: null } = creating, { pool } = editing. */
  const [templateDraft, setTemplateDraft] = useState<{ pool: EnhancedPoolRow | null } | null>(null);

  const requests = useAdminStakingRequests(filter);
  const templates = usePoolTemplates(false);
  const distributions = useRewardDistributions(50);
  const process = useProcessStakingRequest();
  const setTemplateStatus = useSetPoolTemplateStatus();
  const runDistribution = useRunRewardDistribution();

  const rows = requests.data ?? [];
  const templateRows = templates.data ?? [];
  const distributionRows = distributions.data ?? [];

  const distributedTotal = distributionRows.reduce(
    (sum, row) => sum + Number(row.estimated_reward ?? 0),
    0
  );

  function decide(requestId: string, action: 'approve' | 'decline') {
    if (action === 'decline' && !notes.trim()) {
      toast.error('A reason is required to decline a request.');
      return;
    }

    process.mutate(
      { requestId, action, adminNotes: notes },
      {
        onSuccess: () => {
          toast.success(action === 'approve' ? 'Request approved' : 'Request declined');
          setActiveId(null);
          setNotes('');
        },
        onError: (error: Error) =>
          toast.error('Could not process the request', { description: error.message }),
      }
    );
  }

  function toggleTemplate(poolId: string, current: string | null) {
    const next = current === 'active' ? 'paused' : 'active';
    setTemplateStatus.mutate(
      { poolId, status: next },
      {
        onSuccess: () => toast.success(next === 'active' ? 'Pool resumed' : 'Pool paused'),
        onError: (error: Error) =>
          toast.error('Could not update the pool', { description: error.message }),
      }
    );
  }

  function distribute() {
    runDistribution.mutate(undefined, {
      onSuccess: (result) => {
        const paid = result.total_rewards ?? result.total_rewards_distributed ?? 0;
        toast.success('Distribution complete', {
          description: `${result.processed_pools ?? 0} positions processed, ${compact(paid)} credited.`,
        });
      },
      onError: (error: Error) =>
        toast.error('Distribution failed', { description: error.message }),
    });
  }

  return (
    <>
      <PageHeader
        title="Pool management"
        description="Review staking requests, publish pool templates and run reward distribution."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <Stat
          label="Requests in view"
          value={rows.length}
          icon={<Inbox className="size-4" />}
          loading={requests.isLoading}
        />
        <Stat
          label="Published pools"
          value={templateRows.filter((t) => t.status === 'active').length}
          sub={`${templateRows.length} defined`}
          loading={templates.isLoading}
        />
        <Stat
          label="Recent rewards booked"
          value={compact(distributedTotal)}
          tone="success"
          sub={`Last ${distributionRows.length} distributions`}
          loading={distributions.isLoading}
        />
      </div>

      <div className="space-y-6">
        <Section
          title="Request queue"
          description="Approving calls process_staking_request — the position, its rate and the stamped request are written together in the database."
          actions={
            <Segmented
              label="Request status"
              options={FILTER_OPTIONS}
              value={filter}
              onChange={setFilter}
            />
          }
        >
          {requests.isLoading ? (
            <TableSkeleton />
          ) : requests.isError ? (
            <ErrorState error={requests.error} onRetry={() => void requests.refetch()} />
          ) : rows.length === 0 ? (
            <EmptyState
              title="Nothing in this queue"
              description="Requests submitted by members appear here for review."
              icon={<Inbox className="size-5" />}
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Submitted</TH>
                    <TH>Member</TH>
                    <TH>Type</TH>
                    <TH>Token</TH>
                    <TH className="text-right">Amount</TH>
                    <TH>Term</TH>
                    <TH>Status</TH>
                    <TH className="text-right">Decision</TH>
                  </TR>
                </THead>
                <TBody>
                  {rows.map((row) => {
                    const open = activeId === row.id;
                    const pending = row.status === 'pending';
                    return (
                      <TR key={row.id}>
                        <TD className="whitespace-nowrap text-muted-foreground">
                          {shortDate(row.requested_at ?? row.created_at)}
                        </TD>
                        <TD className="max-w-40 truncate">{row.full_name ?? row.user_id}</TD>
                        <TD>
                          <Badge tone={row.request_type === 'unstake' ? 'warning' : 'primary'}>
                            {row.request_type === 'unstake' ? 'Unstake' : 'Stake'}
                          </Badge>
                        </TD>
                        <TD className="font-medium">{poolTypeLabel(row.pool_type)}</TD>
                        <TD className="tabular text-right">
                          {formatToken(Number(row.amount ?? 0), row.pool_type)}
                        </TD>
                        <TD className="tabular">{row.duration_months} mo</TD>
                        <TD>
                          <StatusBadge status={row.status} />
                        </TD>
                        <TD>
                          {!pending ? (
                            <p className="text-right text-xs text-muted-foreground">
                              {row.admin_notes || 'No note'}
                            </p>
                          ) : open ? (
                            <div className="flex flex-col items-end gap-2">
                              <Input
                                value={notes}
                                onChange={(event) => setNotes(event.target.value)}
                                placeholder="Note (required to decline)"
                                aria-label="Decision note"
                                className="max-w-64"
                              />
                              <div className="flex gap-2">
                                <Button
                                  size="sm"
                                  disabled={process.isPending}
                                  onClick={() => decide(row.id, 'approve')}
                                >
                                  {process.isPending ? (
                                    <Loader2 className="animate-spin" />
                                  ) : (
                                    <Check />
                                  )}
                                  Approve
                                </Button>
                                <Button
                                  size="sm"
                                  variant="danger"
                                  disabled={process.isPending}
                                  onClick={() => decide(row.id, 'decline')}
                                >
                                  <X />
                                  Decline
                                </Button>
                                <Button
                                  size="icon"
                                  variant="ghost"
                                  aria-label="Cancel review"
                                  onClick={() => {
                                    setActiveId(null);
                                    setNotes('');
                                  }}
                                >
                                  <X />
                                </Button>
                              </div>
                            </div>
                          ) : (
                            <div className="text-right">
                              <Button
                                size="sm"
                                variant="secondary"
                                onClick={() => {
                                  setActiveId(row.id);
                                  setNotes('');
                                }}
                              >
                                Review
                              </Button>
                            </div>
                          )}
                        </TD>
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>

        <Section
          title="Pool templates"
          description="Advertised rates are read from apr_min and apr_max on each row — the app ships no rate table of its own."
          actions={
            templateDraft ? undefined : (
              <Button size="sm" variant="secondary" onClick={() => setTemplateDraft({ pool: null })}>
                <Plus />
                New pool
              </Button>
            )
          }
        >
          {templateDraft && (
            <PoolTemplateForm
              key={templateDraft.pool?.id ?? 'new'}
              editing={templateDraft.pool}
              onDone={() => setTemplateDraft(null)}
            />
          )}

          {templates.isLoading ? (
            <TableSkeleton />
          ) : templates.isError ? (
            <ErrorState error={templates.error} onRetry={() => void templates.refetch()} />
          ) : templateRows.length === 0 ? (
            <EmptyState
              title="No pool templates defined"
              description="Published pools drive what members can pick when they open a position."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Pool</TH>
                    <TH>Token</TH>
                    <TH>Term</TH>
                    <TH className="text-right">Advertised APR</TH>
                    <TH className="text-right">Min stake</TH>
                    <TH className="text-right">Max stake</TH>
                    <TH>Curve</TH>
                    <TH>Status</TH>
                    <TH className="text-right">Action</TH>
                  </TR>
                </THead>
                <TBody>
                  {templateRows.map((template) => (
                    <TR key={template.id}>
                      <TD className="font-medium">{template.name}</TD>
                      <TD>{poolTypeLabel(template.token_type)}</TD>
                      <TD className="tabular">{template.duration_months} mo</TD>
                      <TD className="tabular text-right">
                        {percent(template.apr_min)} – {percent(template.apr_max)}
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {template.min_stake_amount == null
                          ? '—'
                          : compact(template.min_stake_amount)}
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {template.max_stake_amount == null
                          ? '—'
                          : compact(template.max_stake_amount)}
                      </TD>
                      <TD className="capitalize text-muted-foreground">
                        {template.reward_curve ?? '—'}
                        {template.compounding ? ' · compounding' : ''}
                      </TD>
                      <TD>
                        <StatusBadge status={template.status} />
                      </TD>
                      <TD>
                        <div className="flex items-center justify-end gap-2">
                          <Button
                            size="icon"
                            variant="ghost"
                            aria-label={`Edit ${template.name}`}
                            onClick={() => setTemplateDraft({ pool: template })}
                          >
                            <Pencil />
                          </Button>
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={setTemplateStatus.isPending}
                            onClick={() => toggleTemplate(template.id, template.status)}
                          >
                            {template.status === 'active' ? <Pause /> : <Play />}
                            {template.status === 'active' ? 'Pause' : 'Resume'}
                          </Button>
                        </div>
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>

        <Section
          title="Reward distribution"
          description="The edge function re-checks your admin role server-side, then the database credits eligible positions."
          actions={
            <Button disabled={runDistribution.isPending} onClick={distribute}>
              {runDistribution.isPending && <Loader2 className="animate-spin" />}
              Run vested distribution
            </Button>
          }
        >
          <div className="flex items-start gap-3 border-b border-border p-5 text-sm">
            <ShieldAlert className="mt-0.5 size-4 shrink-0 text-warning" />
            <p className="text-muted-foreground">
              Distribution credits <span className="font-medium text-foreground">rewards_earned</span>{' '}
              on every eligible position. It runs entirely on the server; this page only asks it to
              run and reports what it did.
            </p>
          </div>

          {distributions.isLoading ? (
            <TableSkeleton />
          ) : distributions.isError ? (
            <ErrorState error={distributions.error} onRetry={() => void distributions.refetch()} />
          ) : distributionRows.length === 0 ? (
            <EmptyState
              title="No distributions recorded"
              description="Each run writes a row per position to staking_rewards_distribution."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Date</TH>
                    <TH>Member</TH>
                    <TH className="text-right">Stake</TH>
                    <TH className="text-right">APY applied</TH>
                    <TH className="text-right">Reward</TH>
                    <TH className="text-right">Efficiency</TH>
                    <TH>Status</TH>
                  </TR>
                </THead>
                <TBody>
                  {distributionRows.map((row) => (
                    <TR key={row.id}>
                      <TD className="whitespace-nowrap text-muted-foreground">
                        {shortDate(row.distribution_date)}
                      </TD>
                      <TD className="max-w-40 truncate text-muted-foreground">{row.user_id}</TD>
                      <TD className="tabular text-right">{compact(row.stake_amount)}</TD>
                      <TD className="tabular text-right">{percent(row.calculated_apy)}</TD>
                      <TD className="tabular text-right text-success">
                        {compact(row.estimated_reward)}
                      </TD>
                      <TD className="tabular text-right text-muted-foreground">
                        {row.network_efficiency == null ? '—' : percent(row.network_efficiency * 100)}
                      </TD>
                      <TD>
                        <StatusBadge status={row.status} />
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </Section>
      </div>
    </>
  );
}

function TableSkeleton() {
  return (
    <div className="space-y-3 p-5">
      <Skeleton className="h-9 w-full" />
      <Skeleton className="h-9 w-full" />
      <Skeleton className="h-9 w-full" />
    </div>
  );
}
