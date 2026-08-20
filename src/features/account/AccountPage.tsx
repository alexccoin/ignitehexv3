import { useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { CheckCircle2, Circle } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input, Field } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { Skeleton } from '@/components/ui/skeleton';
import {
  useV2Account,
  useSubmitClaim,
  useAcceptTerms,
  useSubmitForReview,
  MICA_TERMS_VERSION,
} from '@/hooks/data';
import { shortDate } from '@/lib/format';

const CATEGORIES = [
  { value: 'token', label: 'Token' },
  { value: 'fiat', label: 'Fiat' },
  { value: 'str_domain', label: 'STR domain' },
  { value: 'node', label: 'Node' },
  { value: 'banking', label: 'Banking' },
  { value: 'card', label: 'Card' },
  { value: 'equity', label: 'Equity' },
  { value: 'other', label: 'Other' },
];

/** The steps a member works through before assets are credited. */
function Progress({ account, claimCount, verifiedCount }: {
  account: { status: string | null; mica_terms_accepted: boolean | null; submitted_at: string | null } | null;
  claimCount: number;
  verifiedCount: number;
}) {
  const steps = [
    { label: 'Profile started', done: !!account },
    { label: 'Terms accepted', done: !!account?.mica_terms_accepted },
    { label: 'Assets claimed', done: claimCount > 0 },
    { label: 'Submitted for review', done: !!account?.submitted_at },
    { label: 'Verified', done: verifiedCount > 0 || account?.status === 'approved' },
  ];

  return (
    <ol className="space-y-2.5">
      {steps.map((s) => (
        <li key={s.label} className="flex items-center gap-2.5 text-sm">
          {s.done ? (
            <CheckCircle2 className="size-4 shrink-0 text-success" />
          ) : (
            <Circle className="size-4 shrink-0 text-muted-foreground" />
          )}
          <span className={s.done ? 'text-foreground' : 'text-muted-foreground'}>{s.label}</span>
        </li>
      ))}
    </ol>
  );
}

export default function AccountPage() {
  const v2 = useV2Account();
  const submit = useSubmitClaim();
  const acceptTerms = useAcceptTerms();
  const submitForReview = useSubmitForReview();

  const [category, setCategory] = useState('token');
  const [symbol, setSymbol] = useState('');
  const [amount, setAmount] = useState('');
  const [reference, setReference] = useState('');

  const account = v2.data?.account ?? null;
  const claims = v2.data?.claims ?? [];
  const assets = v2.data?.assets ?? [];

  /**
   * Whether the member may still change this account.
   *
   * These two mirror the database exactly rather than approximating it. The
   * own-update policy on v2_accounts has `USING (status IN ('draft','rejected'))`,
   * so an account in any other state matches zero rows on update — which
   * PostgREST reports as `200 []`, not an error. Offering the buttons anyway
   * would produce a control that appears to work and silently does nothing.
   */
  const editable = account?.status === 'draft' || account?.status === 'rejected';
  const canSubmit = editable && !!account?.mica_terms_accepted && claims.length > 0;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (!account) return;

    const parsed = Number(amount);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      toast.error('Enter an amount greater than zero.');
      return;
    }

    try {
      await submit.mutateAsync({
        accountId: account.id,
        category,
        assetSymbol: symbol.trim().toUpperCase(),
        claimedAmount: parsed,
        reference: reference.trim() || undefined,
      });
      toast.success('Claim submitted for verification.');
      setSymbol('');
      setAmount('');
      setReference('');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Could not submit the claim');
    }
  }

  if (v2.isLoading) {
    return (
      <>
        <PageHeader title="Account" />
        <Skeleton className="h-64 w-full" />
      </>
    );
  }

  if (v2.isError) {
    return (
      <>
        <PageHeader title="Account" />
        <Card>
          <ErrorState error={v2.error} onRetry={() => void v2.refetch()} />
        </Card>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title="Account and verification"
        description="Assets are credited only after an administrator verifies each claim."
        actions={account ? <StatusBadge status={account.status} /> : undefined}
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Progress</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 pt-3">
            <Progress account={account} claimCount={claims.length} verifiedCount={assets.length} />

            {/* The two steps a member performs. Without these the list above was
                a status display of things nothing could ever change: terms had
                no way to be accepted and the account had no way to be sent for
                review, so a member could never get past step two. */}
            {account && editable && (
              <div className="space-y-3 border-t border-border pt-4">
                {!account.mica_terms_accepted ? (
                  <div className="space-y-2">
                    <p className="text-sm text-muted-foreground">
                      Before submitting, confirm you accept the platform terms ({MICA_TERMS_VERSION}).
                    </p>
                    <Button
                      size="sm"
                      disabled={acceptTerms.isPending}
                      onClick={() =>
                        acceptTerms.mutate(account.id, {
                          onSuccess: () => toast.success(`Terms ${MICA_TERMS_VERSION} accepted.`),
                          onError: (e) =>
                            toast.error(e instanceof Error ? e.message : 'Could not record acceptance'),
                        })
                      }
                    >
                      {acceptTerms.isPending ? 'Recording…' : 'Accept terms'}
                    </Button>
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    Terms {account.mica_terms_version ?? MICA_TERMS_VERSION} accepted.
                  </p>
                )}

                <div className="space-y-2">
                  <Button
                    size="sm"
                    variant={canSubmit ? 'primary' : 'ghost'}
                    disabled={!canSubmit || submitForReview.isPending}
                    onClick={() =>
                      submitForReview.mutate(account.id, {
                        onSuccess: () => toast.success('Sent for review.'),
                        onError: (e) =>
                          toast.error(e instanceof Error ? e.message : 'Could not submit'),
                      })
                    }
                  >
                    {submitForReview.isPending ? 'Submitting…' : 'Submit for review'}
                  </Button>
                  {/* Say which prerequisite is missing rather than presenting a
                      disabled button with no explanation. */}
                  {!canSubmit && (
                    <p className="text-xs text-muted-foreground">
                      {!account.mica_terms_accepted
                        ? 'Accept the terms first.'
                        : 'Add at least one asset claim first.'}
                    </p>
                  )}
                </div>
              </div>
            )}

            {account && !editable && account.status !== 'approved' && (
              <p className="border-t border-border pt-4 text-sm text-muted-foreground">
                Your account is with an administrator. You cannot change it while it is under review.
              </p>
            )}

            {account?.rejection_reason && (
              <p className="mt-4 rounded-md border border-danger/30 bg-danger/5 p-3 text-sm text-danger">
                {account.rejection_reason}
              </p>
            )}
            {account?.review_notes && !account.rejection_reason && (
              <p className="mt-4 rounded-md border border-border bg-elevated p-3 text-sm text-muted-foreground">
                {account.review_notes}
              </p>
            )}
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <div>
              <CardTitle>Claim an asset</CardTitle>
              <CardDescription>
                Tell us what you hold. Nothing is credited until it is verified.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="pt-4">
            {!account ? (
              <EmptyState
                title="No account record yet"
                description="Your V2 account is created when you first sign in. Try reloading."
              />
            ) : (
              <form onSubmit={onSubmit} className="grid gap-4 sm:grid-cols-2">
                <Field label="Category" htmlFor="category">
                  <select
                    id="category"
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                    className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c.value} value={c.value}>
                        {c.label}
                      </option>
                    ))}
                  </select>
                </Field>

                <Field label="Asset symbol" htmlFor="symbol">
                  <Input
                    id="symbol"
                    value={symbol}
                    onChange={(e) => setSymbol(e.target.value)}
                    placeholder="STR"
                    required
                  />
                </Field>

                <Field label="Amount held" htmlFor="amount">
                  <Input
                    id="amount"
                    type="number"
                    min="0"
                    step="any"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    required
                  />
                </Field>

                <Field label="Reference" htmlFor="reference" hint="Transaction hash or receipt, if you have one.">
                  <Input id="reference" value={reference} onChange={(e) => setReference(e.target.value)} />
                </Field>

                <div className="sm:col-span-2">
                  <Button type="submit" disabled={submit.isPending}>
                    {submit.isPending ? 'Submitting…' : 'Submit claim'}
                  </Button>
                </div>
              </form>
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Your claims</CardTitle>
        </CardHeader>
        <CardContent className="pt-3">
          {claims.length === 0 ? (
            <EmptyState title="No claims yet" description="Submit a claim above to begin verification." />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Asset</TH>
                    <TH>Category</TH>
                    <TH>Claimed</TH>
                    <TH>Verified</TH>
                    <TH>Status</TH>
                    <TH>Submitted</TH>
                  </TR>
                </THead>
                <TBody>
                  {claims.map((c) => (
                    <TR key={c.id}>
                      <TD className="font-medium uppercase">{c.asset_symbol}</TD>
                      <TD className="text-muted-foreground">{c.category}</TD>
                      <TD className="tabular">{Number(c.claimed_amount ?? 0).toLocaleString()}</TD>
                      <TD className="tabular">
                        {c.verified_amount === null
                          ? '—'
                          : Number(c.verified_amount).toLocaleString()}
                      </TD>
                      <TD>
                        <StatusBadge status={c.status} />
                      </TD>
                      <TD className="text-muted-foreground">{shortDate(c.created_at)}</TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}
        </CardContent>
      </Card>
    </>
  );
}
