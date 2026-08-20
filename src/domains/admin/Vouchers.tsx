import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { FileWarning, RefreshCw, Search } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import {
  useCorrectPrecexVouchers,
  useCorrectTargetedStrVouchers,
  useCorrectVoucherAmount,
  useCorrectVoucherTokens,
  useExposureIndex,
  useVoucherDecision,
  useVoucherQueue,
  type VoucherRow,
} from './hooks';
import { scoreRisk, type RiskResult } from './lib/safeMode';
import type { ExposureRow } from './lib/platformExposure';
import { num, usdFromPackage, voucherTokens } from './lib/valuation';
import { LevelBadge, PhraseConfirm, SafeModeBanner } from './components';

/**
 * Voucher risk review.
 *
 * This is the screen safe mode was written for. A voucher decision credits
 * tokens into a member's pools, so every action here — approval, rejection and
 * both correction routines — is behind the typed phrase, and every one of them
 * runs through a server function that does the crediting itself. The browser
 * never computes a token amount and sends it.
 *
 * The one exception is the Pre-CEX dry run, which is permitted while safe mode
 * is armed because counting what would change writes nothing. Being able to see
 * the size of a correction before unlocking the console is the point.
 */

const usdFormat = (value: number) => money(value, 'USD');
const errorMessage = (error: unknown, fallback: string) =>
  error instanceof Error ? error.message : fallback;

const STATUSES = ['pending', 'approved', 'rejected', 'all'] as const;

interface ScoredVoucher {
  voucher: VoucherRow;
  risk: RiskResult;
  declaredUsd: number;
  expectedTokens: number;
  duplicateProof: boolean;
  missingProof: boolean;
}

export default function Vouchers() {
  const [status, setStatus] = useState<string>('pending');
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [correctedAmount, setCorrectedAmount] = useState('');

  const queue = useVoucherQueue(status);
  // Reuses the exposure sweep's cache rather than re-querying the asset tables:
  // the risk score for a voucher depends on what the member already holds.
  const exposure = useExposureIndex();

  const decide = useVoucherDecision();
  const correctTokens = useCorrectVoucherTokens();
  const correctAmount = useCorrectVoucherAmount();
  const precex = useCorrectPrecexVouchers();
  const targeted = useCorrectTargetedStrVouchers();

  const exposureByUser = useMemo(() => {
    const map = new Map<string, ExposureRow>();
    for (const row of exposure.data?.rows ?? []) map.set(row.userId, row);
    return map;
  }, [exposure.data]);

  const scored = useMemo((): ScoredVoucher[] => {
    const vouchers = queue.data ?? [];

    // Payment references that appear on more than one voucher.
    const proofCounts = new Map<string, number>();
    const perUser = new Map<string, { count: number; tokens: number }>();

    for (const voucher of vouchers) {
      const proof = String(voucher.payment_hash || voucher.confirmation_number || '')
        .trim()
        .toLowerCase();
      if (proof.length >= 6) proofCounts.set(proof, (proofCounts.get(proof) ?? 0) + 1);

      const tally = perUser.get(voucher.user_id) ?? { count: 0, tokens: 0 };
      tally.count += 1;
      tally.tokens += voucherTokens(voucher.package_type, voucher.token_type);
      perUser.set(voucher.user_id, tally);
    }

    return vouchers.map((voucher) => {
      const proof = String(voucher.payment_hash || voucher.confirmation_number || '')
        .trim()
        .toLowerCase();
      const duplicateProof = proof.length >= 6 && (proofCounts.get(proof) ?? 0) > 1;
      const missingProof =
        !voucher.payment_hash && !voucher.confirmation_number && !voucher.proof_of_payment_url;

      const member = exposureByUser.get(voucher.user_id);
      const tally = perUser.get(voucher.user_id) ?? { count: 1, tokens: 0 };
      const declaredUsd = usdFromPackage(voucher.package_type) || num(voucher.amount);

      const risk = scoreRisk({
        voucherCount: tally.count,
        uncreditedCount: member?.uncreditedCount ?? 0,
        voucherTokenTotal: tally.tokens,
        usdValue: declaredUsd,
        stakingTotal: member?.breakdown.staking ?? 0,
        fiatTotal: member?.breakdown.fiat ?? 0,
        cryptoTotal: member?.breakdown.crypto ?? 0,
        sharesTotal: member?.breakdown.shares ?? 0,
        safeUsdTotal: member?.breakdown.safeEquity ?? 0,
        distinctEmails: 1,
        distinctNames: 1,
        duplicateHash: duplicateProof,
        missingPaymentProof: missingProof,
        // Account age is not readable from the voucher queue, and a wrong age
        // would score a signal that was never measured. -1 leaves the rule out
        // rather than guessing at it.
        accountAgeDays: -1,
        profileApproved: (member?.accountStatus ?? 'approved') === 'approved',
      });

      return {
        voucher,
        risk,
        declaredUsd,
        expectedTokens: voucherTokens(voucher.package_type, voucher.token_type),
        duplicateProof,
        missingProof,
      };
    });
  }, [queue.data, exposureByUser]);

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return scored;
    return scored.filter((entry) =>
      [
        entry.voucher.full_name,
        entry.voucher.email_address,
        entry.voucher.package_type,
        entry.voucher.payment_hash,
        entry.voucher.user_id,
      ].some((field) => String(field ?? '').toLowerCase().includes(query))
    );
  }, [scored, search]);

  const selected = filtered.find((entry) => entry.voucher.id === selectedId) ?? null;

  const totals = useMemo(() => {
    let pendingUsd = 0;
    let duplicates = 0;
    let noProof = 0;
    for (const entry of scored) {
      if (!entry.voucher.tokens_credited) pendingUsd += entry.declaredUsd;
      if (entry.duplicateProof) duplicates += 1;
      if (entry.missingProof) noProof += 1;
    }
    return { pendingUsd, duplicates, noProof };
  }, [scored]);

  const busy =
    decide.isPending || correctTokens.isPending || correctAmount.isPending;

  const runDecision = (next: 'approved' | 'rejected', phrase: string) => {
    if (!selected) return;
    decide.mutate(
      {
        voucherId: selected.voucher.id,
        status: next,
        notes: notes.trim() || undefined,
        confirmation: phrase,
      },
      {
        onSuccess: () => {
          toast.success(`Voucher ${next}.`);
          setNotes('');
          setSelectedId(null);
        },
        onError: (error) => toast.error(errorMessage(error, 'The decision was refused.')),
      }
    );
  };

  return (
    <>
      <PageHeader
        title="Voucher review"
        description="Score, triage and decide voucher redemptions. Every decision credits or refuses tokens, so all of them sit behind safe mode."
        actions={
          <Button
            variant="ghost"
            size="icon"
            aria-label="Reload the voucher queue"
            onClick={() => void queue.refetch()}
            disabled={queue.isFetching}
          >
            <RefreshCw className={queue.isFetching ? 'animate-spin' : ''} />
          </Button>
        }
      />

      <SafeModeBanner />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="In this queue" value={scored.length} loading={queue.isLoading} />
        <Stat
          label="Uncredited value"
          value={usdFormat(totals.pendingUsd)}
          loading={queue.isLoading}
          tone={totals.pendingUsd > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Shared payment proof"
          value={totals.duplicates}
          loading={queue.isLoading}
          tone={totals.duplicates > 0 ? 'danger' : 'default'}
        />
        <Stat
          label="No payment proof"
          value={totals.noProof}
          loading={queue.isLoading}
          tone={totals.noProof > 0 ? 'warning' : 'default'}
          icon={<FileWarning className="size-4" />}
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-3 lg:items-start">
        <Card className="lg:col-span-2">
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Queue</CardTitle>
              <CardDescription>
                Select a voucher to review it. Risk is scored from the submission and from what the
                member already holds.
              </CardDescription>
            </div>
          </CardHeader>

          <CardContent className="space-y-3">
            <div className="relative">
              <Search
                className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden="true"
              />
              <Input
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search name, email, package, hash or user id"
                aria-label="Search vouchers"
                className="pl-9"
              />
            </div>
            <div className="flex flex-wrap gap-1" role="group" aria-label="Voucher status">
              {STATUSES.map((option) => (
                <Button
                  key={option}
                  size="sm"
                  variant={option === status ? 'primary' : 'ghost'}
                  aria-pressed={option === status}
                  onClick={() => {
                    setStatus(option);
                    setSelectedId(null);
                  }}
                >
                  {option === 'all' ? 'All' : option}
                </Button>
              ))}
            </div>
          </CardContent>

          <CardContent className="p-0">
            {queue.isLoading ? (
              <div className="p-5">
                <Skeleton className="h-72 w-full" />
              </div>
            ) : queue.isError ? (
              <ErrorState error={queue.error} onRetry={() => void queue.refetch()} />
            ) : filtered.length === 0 ? (
              <EmptyState
                title="Nothing in this queue"
                description="No voucher matches this status and search."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Risk</TH>
                      <TH>Member</TH>
                      <TH>Package</TH>
                      <TH className="text-right">Declared</TH>
                      <TH>Proof</TH>
                      <TH>Status</TH>
                      <TH>Submitted</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {filtered.map((entry) => (
                      <TR
                        key={entry.voucher.id}
                        onClick={() => {
                          setSelectedId(entry.voucher.id);
                          setCorrectedAmount('');
                        }}
                        className={cn(
                          'cursor-pointer',
                          entry.voucher.id === selectedId && 'bg-primary/5'
                        )}
                      >
                        <TD>
                          <LevelBadge level={entry.risk.level} score={entry.risk.score} />
                        </TD>
                        <TD>
                          <p className="font-medium">{entry.voucher.full_name}</p>
                          <p className="text-xs text-muted-foreground">
                            {entry.voucher.email_address}
                          </p>
                        </TD>
                        <TD className="max-w-[14rem]">
                          <p className="truncate text-sm">{entry.voucher.package_type}</p>
                          <p className="text-xs uppercase text-muted-foreground">
                            {entry.voucher.token_type}
                          </p>
                        </TD>
                        <TD className="tabular text-right">{usdFormat(entry.declaredUsd)}</TD>
                        <TD>
                          {entry.duplicateProof ? (
                            <Badge tone="danger">Shared</Badge>
                          ) : entry.missingProof ? (
                            <Badge tone="warning">Missing</Badge>
                          ) : (
                            <Badge tone="success">Present</Badge>
                          )}
                        </TD>
                        <TD>
                          <StatusBadge status={entry.voucher.status} />
                        </TD>
                        <TD className="text-muted-foreground">
                          {shortDate(entry.voucher.created_at)}
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </CardContent>
        </Card>

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Review</CardTitle>
                <CardDescription>
                  {selected ? 'Every action below writes to member balances.' : 'Select a voucher.'}
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-5">
              {!selected ? (
                <EmptyState
                  title="No voucher selected"
                  description="Pick a row from the queue to review it."
                />
              ) : (
                <>
                  <dl className="space-y-2 text-sm">
                    <div className="flex justify-between gap-3">
                      <dt className="text-muted-foreground">Member</dt>
                      <dd className="text-right font-medium">{selected.voucher.full_name}</dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-muted-foreground">Declared value</dt>
                      <dd className="tabular text-right">{usdFormat(selected.declaredUsd)}</dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-muted-foreground">Expected tokens</dt>
                      <dd className="tabular text-right">
                        {selected.expectedTokens.toLocaleString('en-US')}{' '}
                        {selected.voucher.token_type.toUpperCase()}
                      </dd>
                    </div>
                    <div className="flex justify-between gap-3">
                      <dt className="text-muted-foreground">Credited</dt>
                      <dd className="tabular text-right">
                        {selected.voucher.tokens_credited
                          ? num(selected.voucher.credited_amount).toLocaleString('en-US')
                          : 'Not yet'}
                      </dd>
                    </div>
                  </dl>

                  <div className="space-y-1.5">
                    <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      Risk signals
                    </p>
                    <ul className="space-y-1">
                      {selected.risk.reasons.map((reason) => (
                        <li key={reason} className="text-sm text-muted-foreground">
                          · {reason}
                        </li>
                      ))}
                    </ul>
                  </div>

                  <Field label="Decision note" htmlFor="voucher-note" hint="Stored in the audit trail.">
                    <Input
                      id="voucher-note"
                      value={notes}
                      onChange={(event) => setNotes(event.target.value)}
                      placeholder="Why this decision"
                    />
                  </Field>

                  <PhraseConfirm
                    label="Approve and credit"
                    variant="primary"
                    pending={busy}
                    onConfirm={(phrase) => runDecision('approved', phrase)}
                  />

                  <PhraseConfirm
                    label="Reject"
                    pending={busy}
                    onConfirm={(phrase) => runDecision('rejected', phrase)}
                  />

                  <PhraseConfirm
                    label="Recompute tokens from package"
                    description="The server derives the correct token amount from the package type and re-credits the difference."
                    pending={busy}
                    onConfirm={(phrase) =>
                      correctTokens.mutate(
                        { voucherId: selected.voucher.id, confirmation: phrase },
                        {
                          onSuccess: () => toast.success('Voucher tokens recomputed.'),
                          onError: (error) =>
                            toast.error(errorMessage(error, 'The correction was refused.')),
                        }
                      )
                    }
                  />

                  <div className="space-y-2 border-t border-border pt-4">
                    <Field
                      label="Set credited amount"
                      htmlFor="corrected-amount"
                      hint="The only action here where you name a figure. The delta and the previous amount are recorded."
                    >
                      <Input
                        id="corrected-amount"
                        type="number"
                        min={0}
                        step="0.01"
                        value={correctedAmount}
                        onChange={(event) => setCorrectedAmount(event.target.value)}
                        placeholder={String(selected.expectedTokens)}
                      />
                    </Field>
                    <PhraseConfirm
                      label="Apply amount"
                      pending={busy}
                      disabled={correctedAmount.trim() === ''}
                      disabledReason="Enter a corrected amount first."
                      onConfirm={(phrase) =>
                        correctAmount.mutate(
                          {
                            voucherId: selected.voucher.id,
                            correctedAmount: Number(correctedAmount),
                            reason: notes.trim() || 'Risk console voucher amount correction',
                            confirmation: phrase,
                          },
                          {
                            onSuccess: () => {
                              toast.success('Credited amount corrected.');
                              setCorrectedAmount('');
                            },
                            onError: (error) =>
                              toast.error(errorMessage(error, 'The correction was refused.')),
                          }
                        )
                      }
                    />
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Programme corrections</CardTitle>
                <CardDescription>
                  Server-side remediations that span many vouchers at once.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-5">
              <div className="space-y-2">
                <p className="text-sm">
                  <span className="font-medium">Pre-CEX STR vouchers.</span> Redemptions credited at
                  the $0.005 vesting rate instead of the programme's fixed token amounts.
                </p>
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={precex.isPending}
                  onClick={() =>
                    precex.mutate(
                      { dryRun: true, confirmation: '' },
                      {
                        onSuccess: (result) =>
                          toast.success('Dry run complete.', {
                            description: `${result.corrected ?? 0} voucher(s) would be corrected.`,
                          }),
                        onError: (error) =>
                          toast.error(errorMessage(error, 'The dry run failed.')),
                      }
                    )
                  }
                >
                  {precex.isPending ? 'Running…' : 'Dry run'}
                </Button>
                <p className="text-xs text-muted-foreground">
                  A dry run writes nothing and is allowed while safe mode is armed.
                </p>
                <PhraseConfirm
                  label="Apply Pre-CEX corrections"
                  pending={precex.isPending}
                  onConfirm={(phrase) =>
                    precex.mutate(
                      { dryRun: false, confirmation: phrase },
                      {
                        onSuccess: (result) =>
                          toast.success(`${result.corrected ?? 0} voucher(s) corrected.`),
                        onError: (error) =>
                          toast.error(errorMessage(error, 'The correction was refused.')),
                      }
                    )
                  }
                />
              </div>

              <div className="space-y-2 border-t border-border pt-4">
                <p className="text-sm">
                  <span className="font-medium">Targeted $STR corrections.</span> The list of
                  vouchers and their correct amounts lives inside the server function — this console
                  cannot choose either.
                </p>
                <PhraseConfirm
                  label="Run targeted corrections"
                  pending={targeted.isPending}
                  onConfirm={(phrase) =>
                    targeted.mutate(
                      { confirmation: phrase },
                      {
                        onSuccess: (result) =>
                          toast.success(
                            `${result.corrected ?? 0} corrected, ${result.already_correct ?? 0} already right.`,
                            result.failed
                              ? { description: `${result.failed} failed.` }
                              : undefined
                          ),
                        onError: (error) =>
                          toast.error(errorMessage(error, 'The correction was refused.')),
                      }
                    )
                  }
                />
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  );
}
