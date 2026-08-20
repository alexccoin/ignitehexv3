import { useState } from 'react';
import { toast } from 'sonner';
import { CreditCard, Loader2, PlayCircle, ScanEye, ShieldCheck } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Field, Input, Label } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import {
  useAdminBankApplications,
  useAdminCardApplications,
  useApproveBankApplication,
  useBulkProvisionBanking,
  useDecideCardApplication,
  useIssueNetworkCard,
} from './hooks';
import { AsyncSection, ServerActionPending } from './shared';

const FILTERS = ['pending', 'approved', 'rejected', 'all'] as const;

function errorMessage(err: unknown, fallback: string) {
  return err instanceof Error ? err.message : fallback;
}

export default function Admin() {
  const [filter, setFilter] = useState<string>('pending');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [notes, setNotes] = useState('');
  const [targetUserId, setTargetUserId] = useState('');
  const [provisionLimit, setProvisionLimit] = useState('25');

  const applications = useAdminBankApplications(filter);
  const cardApplications = useAdminCardApplications('pending');

  const approve = useApproveBankApplication();
  const decideCard = useDecideCardApplication();
  const issueCard = useIssueNetworkCard();
  const provision = useBulkProvisionBanking();

  const selected = (applications.data ?? []).find((a) => a.id === selectedId) ?? null;

  async function approveApplication(autoCreateProducts: boolean) {
    if (!selected) return;

    try {
      const result = await approve.mutateAsync({
        applicationId: selected.id,
        adminNotes: notes,
        autoCreateProducts,
      });

      if (result.already_approved) {
        toast.info('That application was already approved.');
      } else {
        const created = [
          result.ibans_created ? result.ibans_created + ' IBAN(s)' : null,
          result.cards_created ? result.cards_created + ' card(s)' : null,
        ].filter(Boolean);
        toast.success('Application approved.', {
          description: created.length ? 'Created ' + created.join(' and ') + '.' : undefined,
        });
      }

      setSelectedId(null);
      setNotes('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not approve the application'));
    }
  }

  async function decideCardApplication(id: string, action: 'approve' | 'reject') {
    try {
      const result = await decideCard.mutateAsync({ applicationId: id, action });
      toast.success(
        action === 'approve'
          ? 'Card issued' + (result.card?.card_number ? ': ' + result.card.card_number : '.')
          : 'Card application rejected.'
      );
    } catch (err) {
      toast.error(errorMessage(err, 'Could not process the card application'));
    }
  }

  async function issueNetworkCard() {
    const id = targetUserId.trim();
    if (!id) {
      toast.error('Enter the member user id.');
      return;
    }

    try {
      const result = await issueCard.mutateAsync({ targetUserId: id });
      toast.success('CCoin network card issued.', {
        description: result.card?.card_number,
      });
      setTargetUserId('');
    } catch (err) {
      toast.error(errorMessage(err, 'Could not issue the card'));
    }
  }

  async function runProvisioning(mode: 'preview' | 'execute') {
    const limit = Number(provisionLimit);
    if (!Number.isFinite(limit) || limit < 1 || limit > 500) {
      toast.error('Limit must be between 1 and 500.');
      return;
    }

    try {
      const result = await provision.mutateAsync({ mode, limit });
      toast.success(
        (mode === 'preview' ? 'Preview complete: ' : 'Provisioning complete: ') +
          String(result.processed ?? result.results?.length ?? 0) +
          ' member(s).'
      );
    } catch (err) {
      toast.error(errorMessage(err, 'Could not run provisioning'));
    }
  }

  return (
    <>
      <PageHeader
        title="Banking approvals"
        description="Applications, card issuance and provisioning. Every decision is executed server-side."
      />

      <div className="space-y-6">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Bank applications</CardTitle>
              <CardDescription>
                Approving provisions real accounts. process-ccoin-bank-approval re-checks your
                admin role from the bearer token before it does anything.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-4 p-0 pb-2">
            <div className="flex flex-wrap gap-2 px-5 pt-5">
              {FILTERS.map((f) => (
                <button
                  key={f}
                  onClick={() => {
                    setFilter(f);
                    setSelectedId(null);
                  }}
                  className={cn(
                    'rounded-full px-3 py-1 text-xs font-medium capitalize ring-1 ring-inset transition-colors',
                    filter === f
                      ? 'bg-primary/10 text-primary ring-primary/20'
                      : 'bg-elevated text-muted-foreground ring-border hover:text-foreground'
                  )}
                >
                  {f}
                </button>
              ))}
            </div>

            <AsyncSection
              query={applications}
              emptyTitle="Nothing to review"
              emptyDescription="No applications match this filter."
              skeletonClassName="mx-5 h-40"
            >
              {(rows) => (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Applicant</TH>
                        <TH>Type</TH>
                        <TH>Submitted</TH>
                        <TH>Decided</TH>
                        <TH>Status</TH>
                        <TH className="text-right">Review</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((row) => (
                        <TR key={row.id} className={cn(row.id === selectedId && 'bg-elevated/60')}>
                          <TD>
                            <p className="font-medium">{row.full_name}</p>
                            <p className="text-xs text-muted-foreground">{row.email}</p>
                          </TD>
                          <TD className="capitalize text-muted-foreground">
                            {row.account_type ?? 'individual'}
                            {row.company_name ? ' · ' + row.company_name : ''}
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                          <TD className="text-muted-foreground">{shortDate(row.processed_at)}</TD>
                          <TD>
                            <StatusBadge status={row.status} />
                          </TD>
                          <TD className="text-right">
                            <Button
                              size="sm"
                              variant={row.id === selectedId ? 'primary' : 'secondary'}
                              onClick={() => {
                                setSelectedId(row.id === selectedId ? null : row.id);
                                setNotes(row.admin_notes ?? '');
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
                  {selected.full_name}
                </CardTitle>
                <CardDescription>{selected.email}</CardDescription>
              </div>
              <StatusBadge status={selected.status} />
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-1.5">
                <Label htmlFor="admin-notes">Reviewer notes</Label>
                <textarea
                  id="admin-notes"
                  rows={3}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Recorded against the application."
                  className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm placeholder:text-muted-foreground"
                />
              </div>

              <div className="flex flex-wrap gap-2">
                <Button
                  disabled={approve.isPending || selected.status === 'approved'}
                  onClick={() => void approveApplication(false)}
                >
                  {approve.isPending ? <Loader2 className="animate-spin" /> : <ShieldCheck />}
                  Approve
                </Button>
                <Button
                  variant="secondary"
                  disabled={approve.isPending || selected.status === 'approved'}
                  onClick={() => void approveApplication(true)}
                >
                  <PlayCircle />
                  Approve and provision accounts
                </Button>
              </div>

              <ServerActionPending
                label="Reject or suspend this application"
                todo="process-ccoin-bank-approval only implements approval — it has no reject branch. v2 rejected by updating ccoin_bank_applications.status straight from the browser, which leaves no server-verified record of who decided. The function needs an action parameter that writes the status, the notes and processed_by under its own admin check."
              />
            </CardContent>
          </Card>
        )}

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <CreditCard className="size-4 text-primary" />
                Card applications
              </CardTitle>
              <CardDescription>
                Pending CCoin card requests. issue-ccoin-card handles both decisions and issues the
                card on approval.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0 pb-2">
            <AsyncSection
              query={cardApplications}
              emptyTitle="No pending card applications"
              emptyDescription="Requests appear here as members apply."
              skeletonClassName="mx-5 h-32"
            >
              {(rows) => (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Domain</TH>
                        <TH>Member</TH>
                        <TH>Wallet</TH>
                        <TH>Submitted</TH>
                        <TH>Status</TH>
                        <TH className="text-right">Decision</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((row) => (
                        <TR key={row.id}>
                          <TD className="font-mono text-xs">{row.str_domain_name}</TD>
                          <TD className="font-mono text-xs text-muted-foreground">{row.user_id}</TD>
                          <TD className="max-w-[10rem] truncate font-mono text-xs text-muted-foreground">
                            {row.wallet_address ?? '—'}
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(row.created_at)}</TD>
                          <TD>
                            <StatusBadge status={row.status} />
                          </TD>
                          <TD>
                            <div className="flex justify-end gap-2">
                              <Button
                                size="sm"
                                variant="secondary"
                                disabled={decideCard.isPending || row.status !== 'pending'}
                                onClick={() => void decideCardApplication(row.id, 'approve')}
                              >
                                Approve
                              </Button>
                              <Button
                                size="sm"
                                variant="ghost"
                                disabled={decideCard.isPending || row.status !== 'pending'}
                                onClick={() => void decideCardApplication(row.id, 'reject')}
                              >
                                Reject
                              </Button>
                            </div>
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

        <div className="grid gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Issue a network card</CardTitle>
                <CardDescription>
                  The function verifies STR domain ownership and wallet validity before issuing.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <Field
                label="Member user id"
                htmlFor="target-user"
                hint="The auth user id of the member receiving the card."
              >
                <Input
                  id="target-user"
                  value={targetUserId}
                  onChange={(e) => setTargetUserId(e.target.value)}
                  placeholder="00000000-0000-0000-0000-000000000000"
                />
              </Field>
              <Button onClick={() => void issueNetworkCard()} disabled={issueCard.isPending}>
                {issueCard.isPending ? <Loader2 className="animate-spin" /> : <CreditCard />}
                Issue card
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Bulk provisioning</CardTitle>
                <CardDescription>
                  Opens EUR, CHF and GBP accounts for approved members who have none. Preview first
                  — this writes to every member in the batch.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <Field label="Batch size" htmlFor="provision-limit" hint="Between 1 and 500.">
                <Input
                  id="provision-limit"
                  type="number"
                  min="1"
                  max="500"
                  value={provisionLimit}
                  onChange={(e) => setProvisionLimit(e.target.value)}
                />
              </Field>

              <div className="flex flex-wrap gap-2">
                <Button
                  variant="secondary"
                  disabled={provision.isPending}
                  onClick={() => void runProvisioning('preview')}
                >
                  {provision.isPending ? <Loader2 className="animate-spin" /> : <ScanEye />}
                  Preview
                </Button>
                <Button
                  variant="danger"
                  disabled={provision.isPending}
                  onClick={() => void runProvisioning('execute')}
                >
                  <PlayCircle />
                  Execute
                </Button>
              </div>

              {provision.data?.results && provision.data.results.length > 0 && (
                <div className="max-h-56 overflow-y-auto rounded-lg border border-border">
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Member</TH>
                          <TH>Domain</TH>
                          <TH>IBANs</TH>
                          <TH>Wallets</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {provision.data.results.map((r) => (
                          <TR key={r.user_id}>
                            <TD className="max-w-[10rem] truncate">{r.full_name}</TD>
                            <TD className="font-mono text-xs">{r.str_domain}</TD>
                            <TD className="tabular">{r.ibans_created.length}</TD>
                            <TD className="tabular">{r.wallets_created.length}</TD>
                          </TR>
                        ))}
                      </TBody>
                    </Table>
                  </TableWrap>
                </div>
              )}

              <p className="text-xs text-muted-foreground">
                <Badge tone="warning" className="mr-2 align-middle">
                  Care
                </Badge>
                Execute writes IBANs and wallets for every approved member in the batch.
              </p>
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle>Not available from this console</CardTitle>
              <CardDescription>
                Administrative actions v2 performed with direct table writes.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            <ServerActionPending
              label="Credit or adjust a member balance"
              todo="No function covers manual adjustment. It needs a double-entry ledger write, a reason code and the acting admin recorded, or the balance and the ledger silently diverge."
            />
            <ServerActionPending
              label="Release a held treasury transfer"
              todo="No function covers release. Approving a pending_transfers_treasury row has to debit the sender, credit the recipient and settle the CCOS fee in one transaction — not three client-side updates."
            />
            <ServerActionPending
              label="Confirm or reject encrypted IBAN data"
              todo="v2's AdminIbanConfirmations wrote iban_data_confirmations directly. Because iban_accounts has a BEFORE trigger that masks the plaintext columns, confirming requires the encrypted values, which only a function holding the key can read."
            />
          </CardContent>
        </Card>
      </div>
    </>
  );
}
