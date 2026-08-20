import { useState } from 'react';
import { toast } from 'sonner';
import { Check, Globe, Network, Star, Wallet, X } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Field, Input } from '@/components/ui/input';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { Table, TableWrap, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import {
  useConnectDomain,
  useCreateDomainWallet,
  useDomainAvailability,
  useDomainInfrastructure,
  useMyDomains,
  useRequestDomain,
  useSetMainDomain,
} from './hooks';
import { BlockedAction, FormError, RowsSkeleton, Section } from './shared';

const DOMAIN_TYPES = [
  { value: 'personal', label: 'Personal' },
  { value: 'business', label: 'Business' },
  { value: 'premium', label: 'Premium' },
  { value: 'brand', label: 'Brand' },
];

function RequestDomainForm() {
  const [name, setName] = useState('');
  const [domainType, setDomainType] = useState('personal');
  const request = useRequestDomain();
  const availability = useDomainAvailability(name);

  const normalised = name.trim().toLowerCase();
  const wellFormed = /^[a-z0-9-]{3,32}$/.test(normalised);
  const available = availability.data === true;

  const submit = () => {
    request.mutate(
      { domainName: normalised, domainType },
      {
        onSuccess: () => {
          toast.success(`${normalised}.str requested. An operator will review and mint it.`);
          setName('');
        },
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle>Request a domain</CardTitle>
          <CardDescription>
            Your request is created as pending and reviewed by an operator. Nothing is charged here.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Domain name"
            htmlFor="domain-name"
            error={
              normalised && !wellFormed
                ? 'Use 3–32 characters: lowercase letters, numbers or hyphens.'
                : undefined
            }
            hint={wellFormed ? `${normalised}.str` : 'Letters, numbers and hyphens only.'}
          >
            <Input
              id="domain-name"
              value={name}
              autoComplete="off"
              aria-invalid={!!normalised && !wellFormed}
              onChange={(e) => setName(e.target.value)}
            />
          </Field>

          <Field label="Domain type" htmlFor="domain-type">
            <select
              id="domain-type"
              className="flex h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
              value={domainType}
              onChange={(e) => setDomainType(e.target.value)}
            >
              {DOMAIN_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </Field>
        </div>

        {/* Availability is the server's answer, and a failed lookup says so
            rather than reading as "free" — v2's pre-check discarded its error. */}
        {wellFormed && (
          <div aria-live="polite" className="text-sm">
            {availability.isPending ? (
              <span className="text-muted-foreground">Checking availability…</span>
            ) : availability.isError ? (
              <span className="text-danger">
                Availability could not be checked: {(availability.error as Error).message}
              </span>
            ) : available ? (
              <span className="flex items-center gap-1.5 text-success">
                <Check className="size-4" aria-hidden="true" />
                {normalised}.str is available
              </span>
            ) : (
              <span className="flex items-center gap-1.5 text-danger">
                <X className="size-4" aria-hidden="true" />
                {normalised}.str is already taken
              </span>
            )}
          </div>
        )}

        <FormError error={request.error} />

        <Button
          onClick={submit}
          disabled={!wellFormed || !available || request.isPending || availability.isPending}
        >
          {request.isPending ? 'Submitting…' : 'Request domain'}
        </Button>
      </CardContent>
    </Card>
  );
}

export default function Domains() {
  const domains = useMyDomains();
  const infra = useDomainInfrastructure();
  const setMain = useSetMainDomain();
  const connect = useConnectDomain();
  const createWallet = useCreateDomainWallet();

  const rows = domains.data ?? [];
  const minted = rows.filter((d) => d.status === 'minted');
  const pending = rows.filter((d) => d.status === 'pending');
  const wallets = infra.data?.wallets ?? [];
  const nodes = infra.data?.nodes ?? [];
  const connections = infra.data?.connections ?? [];

  return (
    <>
      <PageHeader
        title="STR domains"
        description="Your .str identities, their network connections, nodes and wallets."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Minted"
          value={minted.length}
          icon={<Globe className="size-4" />}
          loading={domains.isPending}
        />
        <Stat label="Awaiting approval" value={pending.length} loading={domains.isPending} />
        <Stat
          label="Nodes"
          value={nodes.length}
          icon={<Network className="size-4" />}
          loading={infra.isPending}
        />
        <Stat
          label="Domain wallets"
          value={wallets.length}
          icon={<Wallet className="size-4" />}
          loading={infra.isPending}
        />
      </div>

      <div className="space-y-8">
        <Section title="Your domains">
          <Card>
            {domains.isPending ? (
              <RowsSkeleton />
            ) : domains.isError ? (
              <ErrorState error={domains.error} onRetry={() => void domains.refetch()} />
            ) : rows.length === 0 ? (
              <EmptyState
                icon={<Globe className="size-5" />}
                title="No domains yet"
                description="Request your first .str identity below."
              />
            ) : (
              <>
                <FormError error={setMain.error ?? connect.error ?? createWallet.error} />
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Domain</TH>
                        <TH>Type</TH>
                        <TH>Status</TH>
                        <TH>Network</TH>
                        <TH>Wallet</TH>
                        <TH>Minted</TH>
                        <TH>Actions</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((domain) => {
                        const wallet = wallets.find((w) => w.domain_id === domain.id);
                        const connection = connections.find(
                          (c) => c.domain_name === domain.domain_name
                        );
                        return (
                          <TR key={domain.id}>
                            <TD>
                              <div className="flex items-center gap-2">
                                <span className="font-medium">{domain.domain_name}.str</span>
                                {domain.is_main_domain && (
                                  <Badge tone="primary">
                                    <Star className="size-3" aria-hidden="true" />
                                    Main
                                  </Badge>
                                )}
                              </div>
                            </TD>
                            <TD className="text-muted-foreground">{domain.domain_type}</TD>
                            <TD>
                              <StatusBadge status={domain.status} />
                            </TD>
                            <TD>
                              {connection ? (
                                <StatusBadge status={connection.connection_status} />
                              ) : (
                                <span className="text-muted-foreground">Not connected</span>
                              )}
                            </TD>
                            <TD className="font-mono text-xs">
                              {wallet ? (
                                `${wallet.wallet_address.slice(0, 10)}…${wallet.wallet_address.slice(-6)}`
                              ) : (
                                <span className="font-sans text-muted-foreground">None</span>
                              )}
                            </TD>
                            <TD className="text-muted-foreground">{shortDate(domain.minted_at)}</TD>
                            <TD>
                              <div className="flex flex-wrap items-center gap-2">
                                {domain.status === 'minted' && !domain.is_main_domain && (
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    disabled={setMain.isPending}
                                    onClick={() =>
                                      setMain.mutate(domain.id, {
                                        onSuccess: () =>
                                          toast.success(
                                            `${domain.domain_name}.str is now your main domain.`
                                          ),
                                      })
                                    }
                                  >
                                    Set as main
                                  </Button>
                                )}
                                {domain.status === 'minted' && !connection && (
                                  <Button
                                    variant="secondary"
                                    size="sm"
                                    disabled={connect.isPending}
                                    onClick={() =>
                                      connect.mutate(
                                        { domainName: domain.domain_name, existingId: null },
                                        {
                                          onSuccess: () =>
                                            toast.success('Network connection requested.'),
                                        }
                                      )
                                    }
                                  >
                                    Connect
                                  </Button>
                                )}
                                {domain.status === 'minted' && !wallet && (
                                  <Button
                                    variant="secondary"
                                    size="sm"
                                    disabled={createWallet.isPending}
                                    onClick={() =>
                                      createWallet.mutate(domain.id, {
                                        onSuccess: () =>
                                          toast.success('Domain wallet created.'),
                                      })
                                    }
                                  >
                                    Create wallet
                                  </Button>
                                )}
                                {domain.status === 'pending' && (
                                  <span className="text-xs text-muted-foreground">
                                    Awaiting operator review
                                  </span>
                                )}
                                {domain.status === 'approved' && (
                                  /*
                                   * TODO(server): minting writes `status = 'minted'` and then
                                   * provisions a keypair. v2 did both from the client
                                   * (DomainMinting.tsx:405-422) and, in the bulk path, threw
                                   * away the wallet function's result entirely (:615-620), so
                                   * a failed provision still reported success and left the
                                   * domain minted with no wallet. Needs
                                   * `mint_str_domain(p_domain_id)` to flip the status and
                                   * create the wallet in one server-side transaction.
                                   */
                                  <BlockedAction
                                    label="Mint"
                                    reason="Minting is an operator action: it must flip the domain and provision its keypair together, which no client-callable function does."
                                  />
                                )}
                              </div>
                            </TD>
                          </TR>
                        );
                      })}
                    </TBody>
                  </Table>
                </TableWrap>
              </>
            )}
          </Card>
        </Section>

        <RequestDomainForm />

        <Section
          title="Network nodes"
          description="Validator and personal nodes assigned to your domains."
        >
          <Card>
            {infra.isPending ? (
              <RowsSkeleton rows={3} />
            ) : infra.isError ? (
              <ErrorState error={infra.error} onRetry={() => void infra.refetch()} />
            ) : nodes.length === 0 ? (
              <EmptyState
                icon={<Network className="size-5" />}
                title="No nodes assigned"
                description="Nodes are assigned to a domain once it is minted and connected."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Domain</TH>
                      <TH>Type</TH>
                      <TH>Status</TH>
                      <TH>Primary</TH>
                      <TH>Assigned</TH>
                      <TH>Last sync</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {nodes.map((node) => {
                      const domain = rows.find((d) => d.id === node.domain_id);
                      return (
                        <TR key={node.id}>
                          <TD className="font-medium">
                            {domain ? `${domain.domain_name}.str` : '—'}
                          </TD>
                          <TD className="text-muted-foreground">{node.node_type}</TD>
                          <TD>
                            <StatusBadge status={node.node_status} />
                          </TD>
                          <TD>
                            {node.is_primary ? <Badge tone="primary">Primary</Badge> : '—'}
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(node.assigned_at)}</TD>
                          <TD className="text-muted-foreground">{shortDate(node.last_sync)}</TD>
                        </TR>
                      );
                    })}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Card>
        </Section>
      </div>
    </>
  );
}
