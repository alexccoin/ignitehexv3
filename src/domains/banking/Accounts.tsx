import { Building2, ShieldCheck, Store, Wallet } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Stat } from '@/components/ui/stat';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { useFiatWallets, useIbans } from '@/hooks/data';
import { maskIban, money } from '@/lib/format';
import { useBankApplication, useBankingProfile, useMerchantIbans } from './hooks';
import { AsyncSection, ApprovalGate, ServerActionPending } from './shared';

export default function Accounts() {
  const application = useBankApplication();
  const profile = useBankingProfile();
  const wallets = useFiatWallets();
  const ibans = useIbans();
  const merchant = useMerchantIbans();

  const gateLoading = application.isLoading || profile.isLoading;
  const approved = application.data?.status === 'approved' || !!profile.data;

  const encryptedCount = (ibans.data ?? []).filter((i) => i.is_data_encrypted).length;
  const activeCount = (ibans.data ?? []).filter((i) => i.status === 'active').length;

  return (
    <>
      <PageHeader
        title="Accounts"
        description="Multi-currency IBANs, fiat balances and merchant accounts."
      />

      {gateLoading ? (
        <Skeleton className="h-48 w-full" />
      ) : !approved ? (
        <ApprovalGate status={application.data?.status} />
      ) : (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-3">
            <Stat
              label="IBANs"
              value={String((ibans.data ?? []).length)}
              sub={activeCount + ' active'}
              icon={<Building2 className="size-4" />}
              loading={ibans.isLoading}
            />
            <Stat
              label="Fiat wallets"
              value={String((wallets.data ?? []).length)}
              sub="One per currency"
              icon={<Wallet className="size-4" />}
              loading={wallets.isLoading}
            />
            <Stat
              label="Encrypted at rest"
              value={encryptedCount + ' / ' + String((ibans.data ?? []).length)}
              sub="Account numbers held encrypted"
              icon={<ShieldCheck className="size-4" />}
              tone={encryptedCount > 0 ? 'success' : 'default'}
              loading={ibans.isLoading}
            />
          </div>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Bank accounts</CardTitle>
                <CardDescription>
                  Account numbers are masked everywhere in this app. Where the row is encrypted the
                  database itself only holds a placeholder in the plaintext column.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={ibans}
                emptyTitle="No bank accounts yet"
                emptyDescription="IBANs are provisioned once your application is approved."
                skeletonClassName="mx-5 h-40"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>IBAN</TH>
                          <TH>BIC</TH>
                          <TH>Currency</TH>
                          <TH>Type</TH>
                          <TH className="text-right">Balance</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((account) => (
                          <TR key={account.id}>
                            <TD className="font-mono text-xs">
                              <div className="flex items-center gap-2">
                                {maskIban(account.iban)}
                                {account.is_data_encrypted && (
                                  <Badge tone="success">Encrypted</Badge>
                                )}
                              </div>
                            </TD>
                            <TD className="font-mono text-xs text-muted-foreground">
                              {account.is_data_encrypted ? 'Encrypted' : (account.bic ?? '—')}
                            </TD>
                            <TD className="font-medium">{account.currency}</TD>
                            <TD className="text-muted-foreground">{account.account_type}</TD>
                            <TD className="tabular text-right">
                              {money(Number(account.balance ?? 0), account.currency)}
                            </TD>
                            <TD>
                              <StatusBadge status={account.status} />
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

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle className="flex items-center gap-2">
                  <Store className="size-4 text-muted-foreground" />
                  Merchant accounts
                </CardTitle>
                <CardDescription>Business IBANs held through a merchant profile.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={merchant}
                emptyTitle="No merchant accounts"
                emptyDescription="Business IBANs appear here once a merchant profile is approved."
                skeletonClassName="mx-5 h-32"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>IBAN</TH>
                          <TH>Holder</TH>
                          <TH>Currency</TH>
                          <TH className="text-right">Balance</TH>
                          <TH>Status</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((row) => (
                          <TR key={row.id}>
                            <TD className="font-mono text-xs">
                              <div className="flex items-center gap-2">
                                {maskIban(row.iban)}
                                {row.is_encrypted && <Badge tone="success">Encrypted</Badge>}
                              </div>
                            </TD>
                            <TD>{row.account_holder}</TD>
                            <TD className="font-medium">{row.currency}</TD>
                            <TD className="tabular text-right">
                              {money(Number(row.balance ?? 0), row.currency)}
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
              </AsyncSection>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Fiat wallets</CardTitle>
                <CardDescription>
                  Held balance is committed to a pending movement and cannot be spent twice.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <AsyncSection
                query={wallets}
                emptyTitle="No fiat wallets"
                emptyDescription="A wallet is created for each currency you hold an account in."
                skeletonClassName="mx-5 h-32"
              >
                {(rows) => (
                  <TableWrap>
                    <Table>
                      <THead>
                        <TR>
                          <TH>Currency</TH>
                          <TH className="text-right">Balance</TH>
                          <TH className="text-right">Available</TH>
                          <TH className="text-right">Held</TH>
                        </TR>
                      </THead>
                      <TBody>
                        {rows.map((wallet) => (
                          <TR key={wallet.id}>
                            <TD className="font-medium">{wallet.currency}</TD>
                            <TD className="tabular text-right">
                              {money(Number(wallet.balance ?? 0), wallet.currency)}
                            </TD>
                            <TD className="tabular text-right">
                              {money(Number(wallet.available_balance ?? 0), wallet.currency)}
                            </TD>
                            <TD className="tabular text-right text-warning">
                              {money(Number(wallet.held_balance ?? 0), wallet.currency)}
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

          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Account operations</CardTitle>
                <CardDescription>
                  Actions that change or expose account data need a server-side path before they can
                  be offered.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-3">
              <ServerActionPending
                label="Reveal full IBAN"
                todo="Needs an edge function that decrypts encrypted_iban with the server-held key, writes an access audit row, and returns the value for a single view. The browser must never hold the decryption key, and the plaintext column reads '***ENCRYPTED***' once validate_iban_or_mask has run."
              />
              <ServerActionPending
                label="Open an additional currency account"
                todo="No member-facing function exists. bulk-provision-banking is admin-only and operates over every approved member; a single-member 'open account' function is needed, or route the request through the application flow."
              />
              <ServerActionPending
                label="Close or suspend an account"
                todo="No edge function covers closure. It must move any residual balance, settle pending holds and record who authorised it — none of which can be trusted to a client-side update."
              />
            </CardContent>
          </Card>
        </div>
      )}
    </>
  );
}
