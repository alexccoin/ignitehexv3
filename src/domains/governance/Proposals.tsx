import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Plus, ThumbsDown, ThumbsUp, Vote, X } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { percent, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { useCastVote, useCreateProposal, useMyVotes, useProposals, type Proposal } from './hooks';

/** Re-render on a slow tick so the remaining-time labels stay honest. */
function useMinuteTick(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(id);
  }, []);
  return now;
}

function remaining(endsAt: string, now: number): string {
  const ms = new Date(endsAt).getTime() - now;
  if (Number.isNaN(ms)) return 'No deadline';
  if (ms <= 0) return 'Voting closed';
  const hours = Math.floor(ms / 3_600_000);
  if (hours >= 24) return `${Math.floor(hours / 24)}d ${hours % 24}h left`;
  if (hours >= 1) return `${hours}h left`;
  return `${Math.max(1, Math.round(ms / 60_000))}m left`;
}

/** Support / oppose split. Uses the server-maintained tallies on the row. */
function Tally({ proposal }: { proposal: Proposal }) {
  const total = proposal.vote_count ?? 0;
  const support = proposal.support_votes ?? 0;
  const oppose = Math.max(0, total - support);
  const supportShare = total > 0 ? (support / total) * 100 : 0;

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between text-xs">
        <span className="text-success">
          {support} in favour{total > 0 && ` · ${percent(supportShare, 0)}`}
        </span>
        <span className="text-muted-foreground">{oppose} against</span>
      </div>
      <div
        className="flex h-2 overflow-hidden rounded-full bg-elevated"
        role="img"
        aria-label={`${support} of ${total} votes in favour`}
      >
        <div className="bg-success" style={{ width: `${supportShare}%` }} />
        <div className="bg-danger" style={{ width: `${total > 0 ? 100 - supportShare : 0}%` }} />
      </div>
      <p className="text-xs text-muted-foreground">
        {total === 0 ? 'No votes recorded yet' : `${total} votes recorded`}
      </p>
    </div>
  );
}

function NewProposalForm({ onDone }: { onDone: () => void }) {
  const create = useCreateProposal();
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');

  const titleError = title.trim().length > 0 && title.trim().length < 8 ? 'Use at least 8 characters.' : undefined;
  const canSubmit = title.trim().length >= 8 && description.trim().length >= 20 && !create.isPending;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!canSubmit) return;
    try {
      await create.mutateAsync({ title: title.trim(), description: description.trim() });
      toast.success('Proposal opened for voting.');
      setTitle('');
      setDescription('');
      onDone();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not open the proposal');
    }
  }

  return (
    <Card className="mb-6">
      <CardHeader>
        <div className="space-y-1">
          <CardTitle>Open a proposal</CardTitle>
          <CardDescription>Voting runs for 72 hours from the moment it is opened.</CardDescription>
        </div>
        <Button variant="ghost" size="icon" onClick={onDone} aria-label="Discard this proposal">
          <X />
        </Button>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={submit}>
          <Field label="Title" htmlFor="proposal-title" error={titleError} hint="One line stating what is being decided.">
            <Input
              id="proposal-title"
              value={title}
              maxLength={140}
              aria-invalid={!!titleError}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Raise the treasury multisig threshold to 4 of 7"
            />
          </Field>

          <Field
            label="Detail"
            htmlFor="proposal-description"
            hint={`${description.trim().length}/20 characters minimum. Explain the change and its effect.`}
          >
            <textarea
              id="proposal-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={5}
              maxLength={4000}
              className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm transition-colors placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50"
              placeholder="What is being proposed, why, and what changes if it passes."
            />
          </Field>

          <div className="flex gap-2">
            <Button type="submit" disabled={!canSubmit}>
              {create.isPending ? 'Opening…' : 'Open for voting'}
            </Button>
            <Button type="button" variant="ghost" onClick={onDone}>
              Cancel
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}

export default function Proposals() {
  const proposals = useProposals();
  const myVotes = useMyVotes();
  const castVote = useCastVote();
  const [composing, setComposing] = useState(false);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const now = useMinuteTick();

  const rows = useMemo(() => proposals.data ?? [], [proposals.data]);

  const summary = useMemo(() => {
    const open = rows.filter((p) => new Date(p.voting_ends_at).getTime() > now).length;
    return {
      open,
      total: rows.length,
      passed: rows.filter((p) => p.status === 'approved').length,
      votesCast: rows.reduce((sum, p) => sum + (p.vote_count ?? 0), 0),
    };
  }, [rows, now]);

  async function vote(proposal: Proposal, support: boolean) {
    setPendingId(proposal.id);
    try {
      await castVote.mutateAsync({ proposalId: proposal.id, support });
      toast.success(support ? 'Recorded in favour.' : 'Recorded against.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not record your vote');
    } finally {
      setPendingId(null);
    }
  }

  return (
    <>
      <PageHeader
        title="Governance"
        description="Open proposals, cast a vote, and see how the membership decided."
        actions={
          !composing && (
            <Button onClick={() => setComposing(true)}>
              <Plus />
              New proposal
            </Button>
          )
        }
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Open for voting" value={summary.open} loading={proposals.isLoading} tone="primary" />
        <Stat label="Proposals" value={summary.total} loading={proposals.isLoading} />
        <Stat label="Passed" value={summary.passed} loading={proposals.isLoading} tone="success" />
        <Stat label="Votes recorded" value={summary.votesCast} loading={proposals.isLoading} />
      </div>

      {composing && <NewProposalForm onDone={() => setComposing(false)} />}

      {proposals.isLoading ? (
        <div className="space-y-4">
          <Skeleton className="h-44 w-full" />
          <Skeleton className="h-44 w-full" />
        </div>
      ) : proposals.isError ? (
        <Card>
          <ErrorState error={proposals.error} onRetry={() => void proposals.refetch()} />
        </Card>
      ) : rows.length === 0 ? (
        <Card>
          <EmptyState
            title="No proposals yet"
            description="Nothing has been put to the membership. Open the first one."
            icon={<Vote className="size-5" />}
            action={<Button onClick={() => setComposing(true)}>Open a proposal</Button>}
          />
        </Card>
      ) : (
        <div className="space-y-4">
          {rows.map((proposal) => {
            const myVote = myVotes.data?.get(proposal.id);
            const closed = new Date(proposal.voting_ends_at).getTime() <= now;
            const busy = pendingId === proposal.id;
            const locked = closed || !!myVote || busy;

            return (
              <Card key={proposal.id}>
                <CardHeader>
                  <div className="min-w-0 space-y-1">
                    <CardTitle className="truncate">{proposal.title}</CardTitle>
                    <CardDescription>Opened {shortDate(proposal.created_at)}</CardDescription>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <StatusBadge status={proposal.status} />
                    <Badge tone={closed ? 'neutral' : 'info'}>{remaining(proposal.voting_ends_at, now)}</Badge>
                  </div>
                </CardHeader>

                <CardContent className="space-y-4">
                  <p className="whitespace-pre-wrap text-sm text-muted-foreground">{proposal.description}</p>

                  <Tally proposal={proposal} />

                  <div className="flex flex-wrap items-center gap-2">
                    <Button
                      size="sm"
                      variant={myVote?.support === true ? 'primary' : 'secondary'}
                      disabled={locked}
                      onClick={() => void vote(proposal, true)}
                    >
                      <ThumbsUp />
                      In favour
                    </Button>
                    <Button
                      size="sm"
                      variant={myVote?.support === false ? 'danger' : 'secondary'}
                      disabled={locked}
                      onClick={() => void vote(proposal, false)}
                    >
                      <ThumbsDown />
                      Against
                    </Button>
                    <span className={cn('text-xs', myVote ? 'text-foreground' : 'text-muted-foreground')}>
                      {myVote
                        ? `You voted ${myVote.support ? 'in favour' : 'against'} on ${shortDate(myVote.created_at)}`
                        : closed
                          ? 'Voting has closed'
                          : 'You have not voted yet'}
                    </span>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </>
  );
}
