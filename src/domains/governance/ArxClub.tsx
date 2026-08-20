import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import {
  CalendarDays,
  CheckCircle2,
  FileSignature,
  Fingerprint,
  Gavel,
  ShieldCheck,
  Users,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { useAuth } from '@/features/auth/AuthProvider';
import { relativeTime, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import {
  useArxApplications,
  useArxAuditTrail,
  useArxBallots,
  useArxEvents,
  useArxMembership,
  useArxStats,
  useCastBallotVote,
  useMyArxApplication,
  useMyBallotVotes,
  useReviewArxApplication,
  useSubmitArxApplication,
  type ArxApplication,
  type ArxDecision,
} from './hooks';

type Tab = 'ballots' | 'events' | 'attestations' | 'applications';

const BALLOT_CHOICES = ['for', 'against', 'abstain'] as const;

function TabStrip({ tab, setTab, tabs }: { tab: Tab; setTab: (t: Tab) => void; tabs: Array<{ id: Tab; label: string }> }) {
  return (
    <div className="mb-4 flex flex-wrap gap-2">
      {tabs.map(({ id, label }) => (
        <button
          key={id}
          type="button"
          onClick={() => setTab(id)}
          aria-current={tab === id ? 'page' : undefined}
          className={cn(
            'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
            tab === id
              ? 'bg-primary/10 text-primary ring-primary/20'
              : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
          )}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------- membership */

function MembershipPanel() {
  const membership = useArxMembership();
  const application = useMyArxApplication();
  const submit = useSubmitArxApplication();
  const [fullName, setFullName] = useState('');
  const [accepted, setAccepted] = useState({ nda: false, gdpr: false, charter: false });

  if (membership.isLoading || application.isLoading) {
    return <Skeleton className="h-32 w-full" />;
  }

  if (membership.isError) {
    return (
      <Card>
        <ErrorState
          title="Could not load your membership"
          error={membership.error}
          onRetry={() => void membership.refetch()}
        />
      </Card>
    );
  }

  const member = membership.data;

  if (member) {
    return (
      <Card>
        <CardHeader>
          <div className="space-y-1">
            <CardTitle className="flex items-center gap-2">
              <ShieldCheck className="size-5 text-primary" />
              {member.membership_tier} member
            </CardTitle>
            <CardDescription>Joined {shortDate(member.joined_at)}</CardDescription>
          </div>
          <StatusBadge status={member.status} />
        </CardHeader>
        <CardContent className="flex flex-wrap items-center gap-2">
          {member.governance_role && <Badge tone="primary">{member.governance_role}</Badge>}
          {member.council_member && <Badge tone="info">Council</Badge>}
          {member.executive_board && <Badge tone="info">Executive board</Badge>}
          {member.node_operator && <Badge tone="neutral">Node operator</Badge>}
          <Badge tone={member.kyc_status === 'verified' ? 'success' : 'warning'}>
            KYC {member.kyc_status ?? 'pending'}
          </Badge>
          <Badge tone="neutral">Voting weight {member.voting_weight ?? 1}</Badge>
          {member.wnft_credential && (
            <Badge tone="neutral" className="font-mono">
              <Fingerprint className="size-3" />
              {member.wnft_credential}
            </Badge>
          )}
          {member.expires_at && (
            <span className="text-xs text-muted-foreground">Renews {shortDate(member.expires_at)}</span>
          )}
        </CardContent>
      </Card>
    );
  }

  const pending = application.data;
  if (pending) {
    return (
      <Card>
        <CardHeader>
          <div className="space-y-1">
            <CardTitle>Your application</CardTitle>
            <CardDescription>Submitted {shortDate(pending.application_date)}</CardDescription>
          </div>
          <StatusBadge status={pending.status} />
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-muted-foreground">
          <p>
            {pending.status === 'pending'
              ? 'The board has your application. You will get access to the club portal once it is decided.'
              : `This application was ${pending.status}${pending.processed_at ? ` on ${shortDate(pending.processed_at)}` : ''}.`}
          </p>
          {pending.admin_notes && <p className="text-foreground">Note from the board: {pending.admin_notes}</p>}
        </CardContent>
      </Card>
    );
  }

  const allAccepted = accepted.nda && accepted.gdpr && accepted.charter;
  const nameOk = /^[A-Za-z\s'-]{2,100}$/.test(fullName.trim());
  const canSubmit = allAccepted && nameOk && !submit.isPending;

  async function apply(event: React.FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;
    try {
      await submit.mutateAsync({ fullName: fullName.trim() });
      toast.success('Application submitted.');
      setFullName('');
      setAccepted({ nda: false, gdpr: false, charter: false });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the application');
    }
  }

  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2">
            <FileSignature className="size-5 text-primary" />
            Apply for membership
          </CardTitle>
          <CardDescription>
            The board reviews every application. Acceptance timestamps are recorded server-side.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent>
        <form className="max-w-lg space-y-4" onSubmit={apply}>
          <Field
            label="Legal name"
            htmlFor="arx-full-name"
            error={fullName.trim() && !nameOk ? 'Letters, spaces, apostrophes and hyphens only.' : undefined}
            hint="As it appears on the identity document you will present for KYC."
          >
            <Input
              id="arx-full-name"
              value={fullName}
              maxLength={100}
              aria-invalid={!!fullName.trim() && !nameOk}
              onChange={(e) => setFullName(e.target.value)}
            />
          </Field>

          <fieldset className="space-y-2">
            <legend className="text-sm font-medium">Acknowledgements</legend>
            {(
              [
                ['nda', 'I accept the non-disclosure agreement.'],
                ['gdpr', 'I consent to the processing of my data as described in the privacy notice.'],
                ['charter', 'I have read and accept the club charter.'],
              ] as const
            ).map(([key, label]) => (
              <label key={key} className="flex items-start gap-2 text-sm text-muted-foreground">
                <input
                  type="checkbox"
                  className="mt-0.5 size-4 rounded border-input accent-primary"
                  checked={accepted[key]}
                  onChange={(e) => setAccepted((prev) => ({ ...prev, [key]: e.target.checked }))}
                />
                {label}
              </label>
            ))}
          </fieldset>

          <Button type="submit" disabled={!canSubmit}>
            {submit.isPending ? 'Submitting…' : 'Submit application'}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------------------- ballots */

function Ballots() {
  const ballots = useArxBallots();
  const myVotes = useMyBallotVotes();
  const cast = useCastBallotVote();
  const [pending, setPending] = useState<string | null>(null);

  async function vote(ballotId: string, choice: string) {
    setPending(`${ballotId}:${choice}`);
    try {
      await cast.mutateAsync({ ballotId, choice });
      toast.success('Vote recorded.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not record your vote');
    } finally {
      setPending(null);
    }
  }

  if (ballots.isLoading) return <Skeleton className="h-48 w-full" />;
  if (ballots.isError) {
    return (
      <Card>
        <ErrorState error={ballots.error} onRetry={() => void ballots.refetch()} />
      </Card>
    );
  }
  if ((ballots.data ?? []).length === 0) {
    return (
      <Card>
        <EmptyState
          title="No ballots"
          description="Nothing is currently open to the membership."
          icon={<Gavel className="size-5" />}
        />
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {(ballots.data ?? []).map((ballot) => {
        const mine = myVotes.data?.get(ballot.id);
        const open = ballot.status === 'active' && new Date(ballot.voting_end).getTime() > Date.now();

        return (
          <Card key={ballot.id}>
            <CardHeader>
              <div className="min-w-0 space-y-1">
                <CardTitle className="truncate">{ballot.title}</CardTitle>
                <CardDescription>
                  {ballot.ballot_type} · closes {shortDate(ballot.voting_end)}
                  {ballot.quorum_required != null && ` · quorum ${ballot.quorum_required}`}
                </CardDescription>
              </div>
              <StatusBadge status={ballot.status} />
            </CardHeader>
            <CardContent className="space-y-4">
              {ballot.description && (
                <p className="whitespace-pre-wrap text-sm text-muted-foreground">{ballot.description}</p>
              )}

              {ballot.snapshot_hash && (
                <p className="truncate font-mono text-xs text-muted-foreground">
                  Snapshot {ballot.snapshot_hash}
                </p>
              )}

              <div className="flex flex-wrap items-center gap-2">
                {BALLOT_CHOICES.map((choice) => (
                  <Button
                    key={choice}
                    size="sm"
                    variant={mine?.vote_choice === choice ? 'primary' : 'secondary'}
                    disabled={!open || !!mine || pending !== null}
                    onClick={() => void vote(ballot.id, choice)}
                  >
                    {choice === 'for' ? 'For' : choice === 'against' ? 'Against' : 'Abstain'}
                  </Button>
                ))}
                <span className="text-xs text-muted-foreground">
                  {mine
                    ? `You voted "${mine.vote_choice}" with weight ${mine.voting_weight}`
                    : open
                      ? 'Weight is applied by the register when the vote is recorded'
                      : 'This ballot is closed'}
                </span>
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

/* ----------------------------------------------------------------- events */

function Events() {
  const events = useArxEvents();

  if (events.isLoading) return <Skeleton className="h-40 w-full" />;
  if (events.isError) {
    return (
      <Card>
        <ErrorState error={events.error} onRetry={() => void events.refetch()} />
      </Card>
    );
  }
  if ((events.data ?? []).length === 0) {
    return (
      <Card>
        <EmptyState
          title="Nothing scheduled"
          description="No club events are on the calendar."
          icon={<CalendarDays className="size-5" />}
        />
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="p-0">
        <TableWrap>
          <Table>
            <THead>
              <TR>
                <TH>Event</TH>
                <TH>Type</TH>
                <TH>When</TH>
                <TH>Duration</TH>
                <TH>Where</TH>
                <TH>Status</TH>
              </TR>
            </THead>
            <TBody>
              {(events.data ?? []).map((event) => (
                <TR key={event.id}>
                  <TD className="font-medium">{event.event_title}</TD>
                  <TD className="text-muted-foreground">{event.event_type}</TD>
                  <TD className="text-muted-foreground">{shortDate(event.scheduled_at)}</TD>
                  <TD className="text-muted-foreground">
                    {event.duration_minutes ? `${event.duration_minutes} min` : '—'}
                  </TD>
                  <TD className="text-muted-foreground">{event.location ?? 'Online'}</TD>
                  <TD>
                    <StatusBadge status={event.status} />
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </TableWrap>
      </CardContent>
    </Card>
  );
}

/* ----------------------------------------------------------- attestations */

function Attestations() {
  const trail = useArxAuditTrail();

  if (trail.isLoading) return <Skeleton className="h-40 w-full" />;
  if (trail.isError) {
    return (
      <Card>
        <ErrorState error={trail.error} onRetry={() => void trail.refetch()} />
      </Card>
    );
  }
  if ((trail.data ?? []).length === 0) {
    return (
      <Card>
        <EmptyState
          title="No attestations recorded"
          description="Member verifications appear here once the registry writes them."
          icon={<Fingerprint className="size-5" />}
        />
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="space-y-3">
        {(trail.data ?? []).map((entry) => (
          <div
            key={entry.id}
            className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border p-3"
          >
            <div className="flex min-w-0 items-center gap-3">
              <CheckCircle2 className="size-4 shrink-0 text-success" />
              <div className="min-w-0">
                <p className="truncate text-sm font-medium">{entry.action_type}</p>
                <p className="truncate text-xs text-muted-foreground">
                  {entry.resource_type} · {entry.resource_id}
                </p>
              </div>
            </div>
            <div className="text-right">
              {entry.attestation_hash && (
                <p className="max-w-[16rem] truncate font-mono text-xs text-primary">
                  {entry.attestation_hash}
                </p>
              )}
              <p className="text-xs text-muted-foreground">{relativeTime(entry.timestamp)}</p>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

/* ----------------------------------------------------------- applications */

const APPLICATION_FILTERS = ['pending', 'approved', 'declined', 'blocked', 'all'] as const;

function Applications({ canDecide }: { canDecide: boolean }) {
  const [filter, setFilter] = useState<string>('pending');
  const applications = useArxApplications(filter);
  const review = useReviewArxApplication();
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [pending, setPending] = useState<string | null>(null);

  async function decide(application: ArxApplication, decision: ArxDecision) {
    setPending(application.id);
    try {
      await review.mutateAsync({ application, decision, notes: notes[application.id] });
      toast.success(
        decision === 'approved'
          ? `${application.full_name} approved and granted club access.`
          : `Application ${decision}.`
      );
      setNotes((prev) => ({ ...prev, [application.id]: '' }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not record the decision');
    } finally {
      setPending(null);
    }
  }

  return (
    <>
      <div className="mb-4 flex flex-wrap gap-2">
        {APPLICATION_FILTERS.map((f) => (
          <button
            key={f}
            type="button"
            onClick={() => setFilter(f)}
            aria-current={filter === f ? 'true' : undefined}
            className={cn(
              'rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset transition-colors',
              filter === f
                ? 'bg-primary/10 text-primary ring-primary/20'
                : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
            )}
          >
            {f === 'all' ? 'All' : f}
          </button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0">
          {applications.isLoading ? (
            <div className="p-5">
              <Skeleton className="h-40 w-full" />
            </div>
          ) : applications.isError ? (
            <ErrorState error={applications.error} onRetry={() => void applications.refetch()} />
          ) : (applications.data ?? []).length === 0 ? (
            <EmptyState title="Nothing here" description="No applications match this filter." />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Applicant</TH>
                    <TH>Submitted</TH>
                    <TH>Acknowledgements</TH>
                    <TH>Status</TH>
                    {canDecide && <TH className="text-right">Decision</TH>}
                  </TR>
                </THead>
                <TBody>
                  {(applications.data ?? []).map((application) => {
                    const settled = application.status !== 'pending';
                    const busy = pending === application.id;
                    const signed = [
                      application.nda_accepted_at,
                      application.gdpr_accepted_at,
                      application.charter_accepted_at,
                    ].filter(Boolean).length;

                    return (
                      <TR key={application.id}>
                        <TD>
                          <p className="font-medium">{application.full_name}</p>
                          <p className="text-xs text-muted-foreground">{application.email}</p>
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(application.application_date)}</TD>
                        <TD>
                          <Badge tone={signed === 3 ? 'success' : 'warning'}>{signed}/3 signed</Badge>
                        </TD>
                        <TD>
                          <StatusBadge status={application.status} />
                        </TD>
                        {canDecide && (
                          <TD>
                            <div className="flex flex-col items-end gap-2">
                              <Input
                                aria-label={`Decision note for ${application.full_name}`}
                                placeholder="Note (optional)"
                                className="max-w-56"
                                value={notes[application.id] ?? ''}
                                onChange={(e) =>
                                  setNotes((prev) => ({ ...prev, [application.id]: e.target.value }))
                                }
                              />
                              <div className="flex gap-2">
                                <Button
                                  size="sm"
                                  variant="secondary"
                                  disabled={settled || busy}
                                  onClick={() => void decide(application, 'approved')}
                                >
                                  Approve
                                </Button>
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  disabled={settled || busy}
                                  onClick={() => void decide(application, 'declined')}
                                >
                                  Decline
                                </Button>
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  disabled={settled || busy}
                                  onClick={() => void decide(application, 'blocked')}
                                >
                                  Block
                                </Button>
                              </div>
                            </div>
                          </TD>
                        )}
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>
    </>
  );
}

/* ------------------------------------------------------------------- page */

export default function ArxClub() {
  const stats = useArxStats();
  const { hasRole } = useAuth();
  const [tab, setTab] = useState<Tab>('ballots');

  // Presentation only. RLS on arx_applications is what actually decides who can
  // read and decide an application; this just avoids showing decision buttons
  // to a member whose click could only ever fail.
  const canDecide = hasRole('admin');

  const tabs = useMemo(
    () =>
      [
        { id: 'ballots' as const, label: 'Ballots' },
        { id: 'events' as const, label: 'Events' },
        { id: 'attestations' as const, label: 'Attestations' },
        { id: 'applications' as const, label: 'Applications' },
      ] satisfies Array<{ id: Tab; label: string }>,
    []
  );

  return (
    <>
      <PageHeader
        title="ARX Club"
        description="Membership, ballots and the club register."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Active members"
          value={stats.data?.activeMembers ?? 0}
          loading={stats.isLoading}
          icon={<Users className="size-4" />}
        />
        <Stat
          label="Voting council"
          value={stats.data?.council ?? 0}
          loading={stats.isLoading}
          icon={<Gavel className="size-4" />}
        />
        <Stat
          label="Open ballots"
          value={stats.data?.openBallots ?? 0}
          loading={stats.isLoading}
          tone="primary"
        />
        <Stat
          label="Upcoming events"
          value={stats.data?.upcomingEvents ?? 0}
          loading={stats.isLoading}
          icon={<CalendarDays className="size-4" />}
        />
      </div>

      {stats.isError && (
        <Card className="mb-6">
          <ErrorState
            title="Could not load club figures"
            error={stats.error}
            onRetry={() => void stats.refetch()}
          />
        </Card>
      )}

      <div className="mb-6">
        <MembershipPanel />
      </div>

      <TabStrip tab={tab} setTab={setTab} tabs={tabs} />

      {tab === 'ballots' && <Ballots />}
      {tab === 'events' && <Events />}
      {tab === 'attestations' && <Attestations />}
      {tab === 'applications' && <Applications canDecide={canDecide} />}
    </>
  );
}
