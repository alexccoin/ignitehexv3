import { useState } from 'react';
import { toast } from 'sonner';
import { Ban, ClipboardList, Loader2, PauseCircle, ScanEye } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { serviceName } from './properties';
import {
  metadataString,
  useReviewConnection,
  useReviewQueue,
  type AdminDecision,
  type QueueConnection,
} from './hooks';
import { AsyncSection, Note, ServerActionPending } from './shared';

/**
 * The connection review queue.
 *
 * The important thing on this screen is the control that is missing. Approving
 * a link — moving it to `connected` — is a statement that an account exists on
 * the far side under this member's name. Nothing on this deployment can make
 * that statement: there is no edge function for service connections (checked
 * all 90) and no `v2_review_service_connection` routine beside the
 * `v2_review_account` and `v2_review_asset_claim` ones that do exist. An admin
 * *could* write `connected` straight from this browser — the admin UPDATE
 * policy permits it — and that is exactly the v2 habit this rebuild exists to
 * end, so the button is disabled and says what is needed instead.
 *
 * The decisions that are offered assert nothing about the property. Moving a
 * request to `pending_review`, rejecting it and suspending a link are all
 * statements about our own queue, and all of them are reversible.
 */

const FILTERS: { id: string; label: string }[] = [
  { id: 'open', label: 'Open' },
  { id: 'requested', label: 'Requested' },
  { id: 'pending_review', label: 'Pending review' },
  { id: 'connected', label: 'Connected' },
  { id: 'rejected', label: 'Rejected' },
  { id: 'all', label: 'All' },
];

const DECISIONS: { id: AdminDecision; label: string; icon: typeof Ban; variant: 'secondary' | 'danger' }[] = [
  { id: 'pending_review', label: 'Move to review', icon: ScanEye, variant: 'secondary' },
  { id: 'rejected', label: 'Reject', icon: Ban, variant: 'danger' },
  { id: 'suspended', label: 'Suspend', icon: PauseCircle, variant: 'secondary' },
];

/**
 * What a member can actually do to a link row, run against this database.
 *
 * Published in the console because the two "refused silently" rows are the
 * dangerous ones: they return 200 with an empty body, so any caller checking
 * only `error` reads them as success. Whoever next touches this table should
 * see the result before they write against it.
 */
const MEMBER_CAPABILITIES: {
  attempt: string;
  result: string;
  tone: 'success' | 'danger' | 'warning';
  how: string;
}[] = [
  {
    attempt: 'Create a request',
    result: 'Allowed',
    tone: 'success',
    how: 'Insert is restricted to not_connected or requested',
  },
  {
    attempt: 'Re-request after a rejection',
    result: 'Allowed',
    tone: 'success',
    how: 'rejected is one of the two states a member may change',
  },
  {
    attempt: 'Set their own link to connected',
    result: 'Refused loudly',
    tone: 'danger',
    how: '42501 — the WITH CHECK rejects the status outright',
  },
  {
    attempt: 'Cancel their own pending request',
    result: 'Refused silently',
    tone: 'warning',
    how: '200 with an empty body — the USING clause excludes requested',
  },
  {
    attempt: 'Disconnect a connected link',
    result: 'Refused silently',
    tone: 'warning',
    how: '200 with an empty body — the USING clause excludes connected',
  },
  {
    attempt: 'Delete any link row',
    result: 'Refused silently',
    tone: 'warning',
    how: '200 with an empty body — there is no DELETE policy',
  },
];

function errorMessage(err: unknown, fallback: string) {
  return err instanceof Error ? err.message : fallback;
}

export default function Review() {
  const [filter, setFilter] = useState('open');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [note, setNote] = useState('');

  const queue = useReviewQueue(filter);
  const review = useReviewConnection();

  const selected: QueueConnection | null =
    (queue.data ?? []).find((r) => r.id === selectedId) ?? null;

  async function decide(decision: AdminDecision) {
    if (!selected) return;
    try {
      await review.mutateAsync({ id: selected.id, decision, note, current: selected });
      toast.success('Link moved to ' + decision.replace(/_/g, ' ') + '.');
      setSelectedId(null);
      setNote('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not record the decision'));
    }
  }

  return (
    <>
      <PageHeader
        title="Connection review"
        description="Requests to link an IgniteHeX identity to an account on a sibling property."
      />

      <div className="space-y-6">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <ClipboardList className="size-5 text-primary" />
                Review queue
              </CardTitle>
              <CardDescription>
                A member can only ever put a link into <span className="font-mono">requested</span>.
                Everything past that point is decided here.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-4 p-0 pb-2">
            <div className="flex flex-wrap gap-2 px-5 pt-5">
              {FILTERS.map((f) => (
                <button
                  key={f.id}
                  onClick={() => {
                    setFilter(f.id);
                    setSelectedId(null);
                  }}
                  className={cn(
                    'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
                    filter === f.id
                      ? 'bg-primary/10 text-primary ring-primary/20'
                      : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
                  )}
                >
                  {f.label}
                </button>
              ))}
            </div>

            <AsyncSection
              query={queue}
              emptyTitle="Nothing in this queue"
              emptyDescription="No link requests match this filter."
              emptyIcon={<ClipboardList className="size-5" />}
              skeletonClassName="mx-5 h-40"
            >
              {(rows) => (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Property</TH>
                        <TH>Member</TH>
                        <TH>Reference</TH>
                        <TH>Requested</TH>
                        <TH>Status</TH>
                        <TH className="text-right">Review</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((row) => (
                        <TR key={row.id} className={cn(row.id === selectedId && 'bg-elevated/60')}>
                          <TD className="font-medium">{serviceName(row.service)}</TD>
                          <TD className="max-w-[12rem] truncate font-mono text-xs text-muted-foreground">
                            {row.user_id}
                          </TD>
                          <TD className="font-mono text-xs">{row.external_reference ?? '—'}</TD>
                          <TD className="text-muted-foreground">
                            {row.requested_at ? shortDate(row.requested_at) : '—'}
                          </TD>
                          <TD>
                            <StatusBadge status={row.status} />
                          </TD>
                          <TD className="text-right">
                            <Button
                              size="sm"
                              variant={row.id === selectedId ? 'primary' : 'secondary'}
                              onClick={() => {
                                const next = row.id === selectedId ? null : row.id;
                                setSelectedId(next);
                                setNote(next ? metadataString(row.metadata, 'review_note') ?? '' : '');
                              }}
                            >
                              {row.id === selectedId ? 'Close' : 'Review'}
                            </Button>
                          </TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              )}
            </AsyncSection>
          </CardContent>
        </Card>

        {selected && (
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="flex items-center gap-2">
                  <ScanEye className="size-4 text-primary" />
                  {serviceName(selected.service)}
                </CardTitle>
                <CardDescription className="font-mono text-xs">{selected.user_id}</CardDescription>
              </div>
              <StatusBadge status={selected.status} />
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-2 rounded-lg border border-border p-3 text-xs sm:grid-cols-2">
                <div>
                  <span className="text-muted-foreground">Account record: </span>
                  <span className="font-mono">{selected.account_id}</span>
                </div>
                <div>
                  <span className="text-muted-foreground">External reference: </span>
                  <span className="font-mono">{selected.external_reference ?? '—'}</span>
                </div>
                <div>
                  <span className="text-muted-foreground">Requested: </span>
                  {selected.requested_at ? shortDate(selected.requested_at) : '—'}
                </div>
                <div>
                  <span className="text-muted-foreground">Last changed: </span>
                  {shortDate(selected.updated_at)}
                </div>
                <p className="sm:col-span-2">
                  <span className="text-muted-foreground">Metadata: </span>
                  <span className="font-mono break-all">{JSON.stringify(selected.metadata)}</span>
                </p>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="review-note">Reviewer note</Label>
                <textarea
                  id="review-note"
                  rows={3}
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Stored on the link record, and shown to the member."
                  className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm placeholder:text-muted-foreground"
                />
              </div>

              <div className="flex flex-wrap gap-2">
                {DECISIONS.map((d) => {
                  const Icon = d.icon;
                  return (
                    <Button
                      key={d.id}
                      variant={d.variant}
                      disabled={review.isPending || selected.status === d.id}
                      onClick={() => void decide(d.id)}
                    >
                      {review.isPending ? <Loader2 className="animate-spin" /> : <Icon />}
                      {d.label}
                    </Button>
                  );
                })}
              </div>

              {/*
                The one decision this console will not make. Writing `connected`
                from a browser is a claim about a system this deployment cannot
                see, and the row would then be indistinguishable from one a real
                verification produced.
              */}
              <ServerActionPending
                label="Approve — mark this link connected"
                todo={
                  'TODO(server): no routine exists. There is no edge function for service ' +
                  'connections, and no v2_review_service_connection beside v2_review_account and ' +
                  'v2_review_asset_claim. It needs to (1) re-derive the admin from the bearer token ' +
                  'and call has_role itself rather than trusting this guard, (2) confirm the account ' +
                  'on the property — for str.domains against str_domain_connections and its api_key, ' +
                  'for ccoin.finance against nothing that exists yet, (3) set status and connected_at ' +
                  'in one statement, and (4) write a v2_admin_actions row, which no client role can ' +
                  'insert. Until it exists, connected must only ever be set by something that checked.'
                }
              />

              <Note>
                The decisions above are recorded against the link, but not against you: the acting
                admin is not stored. The client could put any id in that column and the policy would
                accept it, so a browser-written actor would be an attribution nobody could rely on.
                It arrives with the routine described above.
              </Note>
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>What a member can do to a link</CardTitle>
              <CardDescription>
                Tested against this database rather than read off the policy text, because two of
                these fail silently.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0 pb-2">
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Attempt</TH>
                    <TH>Result</TH>
                    <TH>How it fails</TH>
                  </TR>
                </THead>
                <TBody>
                  {/*
                    A plain Badge with an explicit tone, not a StatusBadge:
                    these are outcomes of an experiment, not connection
                    statuses, and running them through the status vocabulary
                    would have printed "Approved" next to "Allowed".
                  */}
                  {MEMBER_CAPABILITIES.map((row) => (
                    <TR key={row.attempt}>
                      <TD>{row.attempt}</TD>
                      <TD>
                        <Badge tone={row.tone}>{row.result}</Badge>
                      </TD>
                      <TD className="text-xs text-muted-foreground">{row.how}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
