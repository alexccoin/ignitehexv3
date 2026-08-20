import { useState } from 'react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Table, TableWrap, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Field } from '@/components/ui/input';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Skeleton } from '@/components/ui/skeleton';
import { shortDate } from '@/lib/format';
import {
  useMigrationQueue,
  useQuarantinedBalances,
  useCorrectBalance,
  useApproveMigration,
  useRejectMigration,
  effectiveAmount,
  type MigrationState,
  type QuarantinedBalance,
} from './hooks';

/**
 * The migration review console.
 *
 * This screen is where a legacy figure becomes real money, so it is written to
 * make that hard to do carelessly:
 *
 *  - the claimed figure and the figure that will actually post are shown side
 *    by side, always, even when they are the same;
 *  - approving names the number of ledger legs it will write before you press
 *    it, so a silent no-op is visible as "0 legs";
 *  - rejecting requires a reason, because the database requires one.
 *
 * Nothing here is a guard. Every button calls a SECURITY DEFINER function that
 * re-checks `is_admin()` — this component only decides what to *offer*.
 */

const STATE_TONE: Record<MigrationState, 'warning' | 'info' | 'success' | 'danger'> = {
  quarantined: 'warning',
  under_review: 'info',
  approved: 'success',
  rejected: 'danger',
};

const STATE_LABEL: Record<MigrationState, string> = {
  quarantined: 'Quarantined',
  under_review: 'Under review',
  approved: 'Approved',
  rejected: 'Rejected',
};

const FILTERS: (MigrationState | 'all')[] = ['quarantined', 'under_review', 'approved', 'rejected', 'all'];

function BalanceRow({ b, editable }: { b: QuarantinedBalance; editable: boolean }) {
  const correct = useCorrectBalance();
  const [value, setValue] = useState('');
  const claimed = Number(b.source_amount);
  const effective = effectiveAmount(b);
  const overridden = b.corrected_amount !== null;

  return (
    <TR>
      <TD className="font-medium">{b.asset}</TD>
      <TD className="text-muted-foreground">{b.bucket}</TD>
      <TD className="text-right tabular-nums">{claimed.toLocaleString(undefined, { maximumFractionDigits: 8 })}</TD>
      <TD className="text-right tabular-nums">
        <span className={overridden ? 'text-primary' : 'text-muted-foreground'}>
          {effective.toLocaleString(undefined, { maximumFractionDigits: 8 })}
        </span>
        {overridden && <span className="ml-2 text-xs text-muted-foreground">corrected</span>}
      </TD>
      {editable && (
        <TD>
          <div className="flex items-center gap-2">
            <Input
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder="Override"
              inputMode="decimal"
              className="h-8 w-32"
              aria-label={`Corrected ${b.asset} ${b.bucket} amount`}
            />
            <Button
              size="sm"
              variant="ghost"
              disabled={value.trim() === '' || correct.isPending}
              onClick={() => {
                const n = Number(value);
                if (!Number.isFinite(n) || n < 0) {
                  toast.error('A corrected amount must be zero or positive.');
                  return;
                }
                correct.mutate(
                  { userId: b.user_id, asset: b.asset, bucket: b.bucket, amount: n },
                  {
                    onSuccess: () => {
                      setValue('');
                      toast.success(`${b.asset} ${b.bucket} set to ${n}`);
                    },
                    onError: (e) => toast.error(e instanceof Error ? e.message : 'Could not save'),
                  }
                );
              }}
            >
              Set
            </Button>
          </div>
        </TD>
      )}
    </TR>
  );
}

function AccountDetail({ userId, state }: { userId: string; state: MigrationState }) {
  const balances = useQuarantinedBalances(userId);
  const approve = useApproveMigration();
  const reject = useRejectMigration();
  const [note, setNote] = useState('');
  const open = state === 'quarantined' || state === 'under_review';

  if (balances.isLoading) return <Skeleton className="h-32 w-full" />;
  if (balances.error) return <ErrorState error={balances.error} />;

  const rows = balances.data ?? [];
  // What approval will actually write. Shown before the button is pressed so
  // "approve" is never a guess about what happens next.
  const legs = rows.filter((b) => effectiveAmount(b) > 0).length * 2;

  return (
    <div className="space-y-4">
      {rows.length === 0 ? (
        <EmptyState
          title="No figures were imported"
          description="The legacy platform returned no positive balances for this account. Approving posts nothing and simply opens the account."
        />
      ) : (
        <TableWrap>
          <Table>
            <THead>
              <TR>
                <TH>Asset</TH>
                <TH>Bucket</TH>
                <TH className="text-right">Claimed by legacy</TH>
                <TH className="text-right">Will post</TH>
                {open && <TH>Correct</TH>}
              </TR>
            </THead>
            <TBody>
              {rows.map((b) => (
                <BalanceRow key={b.id} b={b} editable={open} />
              ))}
            </TBody>
          </Table>
        </TableWrap>
      )}

      {open && (
        <div className="space-y-3 border-t border-border pt-4">
          <Field
            label="Decision note"
            htmlFor={`note-${userId}`}
            hint="Required to reject. Recorded against the account either way."
          >
            <Input id={`note-${userId}`} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <div className="flex flex-wrap gap-2">
            <Button
              disabled={approve.isPending}
              onClick={() =>
                approve.mutate(
                  { userId, note: note.trim() || undefined },
                  {
                    onSuccess: (r) =>
                      toast.success(
                        r.legs > 0
                          ? `Approved. ${r.legs} ledger entries posted.`
                          : 'Approved. No balances to post.'
                      ),
                    onError: (e) => toast.error(e instanceof Error ? e.message : 'Could not approve'),
                  }
                )
              }
            >
              {approve.isPending ? 'Posting…' : `Approve and post ${legs} ledger ${legs === 1 ? 'entry' : 'entries'}`}
            </Button>
            <Button
              variant="ghost"
              disabled={reject.isPending || note.trim() === ''}
              onClick={() =>
                reject.mutate(
                  { userId, note: note.trim() },
                  {
                    onSuccess: () => toast.success('Rejected.'),
                    onError: (e) => toast.error(e instanceof Error ? e.message : 'Could not reject'),
                  }
                )
              }
            >
              Reject
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Approval posts each figure above against <code className="font-mono">opening_equity</code>, so the
            credit arrives with a matching debit and a journal reference. It cannot be undone from this screen.
          </p>
        </div>
      )}
    </div>
  );
}

export default function Review() {
  const [filter, setFilter] = useState<MigrationState | 'all'>('quarantined');
  const [openId, setOpenId] = useState<string | null>(null);
  const queue = useMigrationQueue(filter);

  return (
    <>
      <PageHeader
        title="Migration review"
        description="Accounts carried over from the legacy platform. Imported figures are claims until approved here."
      />

      <div className="mb-4 flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <Button key={f} size="sm" variant={filter === f ? 'primary' : 'ghost'} onClick={() => setFilter(f)}>
            {f === 'all' ? 'All' : STATE_LABEL[f]}
          </Button>
        ))}
      </div>

      {queue.isLoading ? (
        <Skeleton className="h-48 w-full" />
      ) : queue.error ? (
        <ErrorState error={queue.error} />
      ) : (queue.data ?? []).length === 0 ? (
        <EmptyState
          title="Nothing here"
          description={
            filter === 'quarantined'
              ? 'No accounts are waiting for a first look.'
              : 'No accounts in this state.'
          }
        />
      ) : (
        <div className="space-y-3">
          {(queue.data ?? []).map((a) => (
            <Card key={a.user_id}>
              <CardHeader className="flex flex-row flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <CardTitle className="truncate text-base">{a.source_email}</CardTitle>
                  <CardDescription>
                    Imported {shortDate(a.imported_at)} from {a.source_project}
                    {a.reviewed_at && ` · decided ${shortDate(a.reviewed_at)}`}
                    {a.review_notes && ` · ${a.review_notes}`}
                  </CardDescription>
                </div>
                <div className="flex items-center gap-2">
                  <Badge tone={STATE_TONE[a.state]}>{STATE_LABEL[a.state]}</Badge>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setOpenId((id) => (id === a.user_id ? null : a.user_id))}
                  >
                    {openId === a.user_id ? 'Close' : 'Review'}
                  </Button>
                </div>
              </CardHeader>
              {openId === a.user_id && (
                <CardContent>
                  <AccountDetail userId={a.user_id} state={a.state} />
                </CardContent>
              )}
            </Card>
          ))}
        </div>
      )}
    </>
  );
}
