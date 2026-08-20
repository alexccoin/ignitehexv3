import { useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from 'sonner';
import {
  ArrowUpRight,
  Fingerprint,
  Loader2,
  Plug,
  RefreshCw,
  ShieldCheck,
  Unplug,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusBadge } from '@/components/ui/status';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { shortDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import { PROPERTIES, UNSURFACED_SERVICES, serviceName, type Property } from './properties';
import {
  isMemberFrozen,
  metadataString,
  useDomainLinks,
  useIdentityAccount,
  useOwnedDomains,
  useRequestConnection,
  useSetConnectionState,
  useServiceConnections,
  type DomainLink,
  type IdentityAccount,
  type ServiceConnection,
} from './hooks';
import { Note, UnverifiableStatus } from './shared';

/**
 * MULTILOGIN — one IgniteHeX identity, four sibling properties.
 *
 * The design rule this screen exists to enforce: a status pill here is a
 * rendering of `v2_service_connections.status` and of nothing else. It is never
 * derived from "we have a row, so we must be connected", never from a prop, and
 * never from an optimistic update. v2's WalletModal drew a "Connected" pill
 * that connected to nothing; every badge below is traceable to one column of
 * one row.
 *
 * Nothing on this page reaches the properties. A browser cannot fetch
 * str.domains or ccoin.finance (cross-origin), and no edge function on this
 * deployment proxies them, so "reachable" is not a thing this screen can
 * measure. Rather than fake a health check, each card states what this
 * deployment actually has behind the property and the footer says plainly that
 * a status is a record, not a live probe.
 */

function errorMessage(err: unknown, fallback: string) {
  return err instanceof Error ? err.message : fallback;
}

/* -------------------------------------------------------------- identity */

/**
 * The one account everything else hangs off.
 *
 * Stated first and stated plainly, because the whole point of the feature is
 * that there is exactly one login. If a member cannot see where their identity
 * lives, the cards below look like four separate accounts again.
 */
function IdentityPanel({ account, email }: { account: IdentityAccount; email: string | null }) {
  return (
    <Card>
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2">
            <Fingerprint className="size-5 text-primary" />
            {account.full_name ?? 'Your IgniteHeX identity'}
          </CardTitle>
          <CardDescription>
            You signed in once, here. Each property below links to this record — none of them holds
            a separate password, and this app never asks you for one.
          </CardDescription>
        </div>
        <StatusBadge status={account.status} />
      </CardHeader>
      <CardContent className="grid gap-3 sm:grid-cols-3">
        {[
          // `capitalize` is applied per field, not to the row: an email address
          // and a domain are identifiers, and title-casing them into
          // "Admin@Ignitehex.Local" makes them look like something the member
          // never typed.
          { label: 'Sign-in address', value: account.email ?? email ?? '—', cap: false },
          {
            label: 'Account mode',
            value: (account.account_mode ?? 'regulated').replace(/_/g, ' '),
            cap: true,
          },
          { label: 'Primary domain', value: account.str_domain ?? 'Not set', cap: false },
        ].map((f) => (
          <div key={f.label} className="rounded-lg border border-border p-3">
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              {f.label}
            </p>
            <p className={cn('mt-1 truncate text-sm font-medium', f.cap && 'capitalize')}>
              {f.value}
            </p>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

/* ---------------------------------------------------- per-domain sub-links */

/**
 * `str_domain_connections` rendered where it belongs: underneath the service it
 * elaborates, not as a card of its own.
 *
 * One row per domain, against `v2_service_connections`'s one row per service.
 * `api_key` is not among the columns requested — see DOMAIN_LINK_COLS in
 * hooks.ts for why that matters.
 */
function DomainLinks({ links }: { links: DomainLink[] }) {
  if (links.length === 0) {
    return (
      <Note>
        No individual domains are registered with the network yet. Each domain you mint gets its own
        row beneath this link.
      </Note>
    );
  }

  return (
    <div className="space-y-2">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Domains registered under this link
      </p>
      <div className="rounded-lg border border-border">
        <TableWrap>
          <Table>
            <THead>
              <TR>
                <TH>Domain</TH>
                <TH>Status</TH>
                <TH>Last sync</TH>
              </TR>
            </THead>
            <TBody>
              {links.map((l) => (
                <TR key={l.id}>
                  <TD className="font-mono text-xs">{l.domain_name}</TD>
                  <TD>
                    <StatusBadge status={l.connection_status} />
                  </TD>
                  <TD className="text-xs text-muted-foreground">
                    {l.last_sync ? shortDate(l.last_sync) : 'Never'}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </TableWrap>
      </div>
      <Note>
        These come from <span className="font-mono">str_domain_connections</span>, one row per
        domain. The card above is the account-level link from{' '}
        <span className="font-mono">v2_service_connections</span>, one row per service.
      </Note>
    </div>
  );
}

/* -------------------------------------------------------------- one card */

function PropertyCard({
  property,
  connection,
  accountId,
  domainLinks,
  suggestions,
}: {
  property: Property;
  connection: ServiceConnection | null;
  accountId: string | null;
  domainLinks: DomainLink[];
  suggestions: string[];
}) {
  const request = useRequestConnection();
  const setState = useSetConnectionState();
  const status = connection?.status ?? 'not_connected';
  const frozen = !!connection && isMemberFrozen(status);
  const recorded = connection ? metadataString(connection.metadata, property.metadataKey) : null;

  const [value, setValue] = useState(recorded ?? suggestions[0] ?? '');
  const Icon = property.icon;

  const canRequest = !!accountId && !frozen;
  const inputId = 'ref-' + property.key;

  async function submit() {
    if (!accountId) return;
    try {
      await request.mutateAsync({
        service: property.key,
        accountId,
        existing: connection,
        metadataKey: property.metadataKey,
        metadataValue: value,
      });
      toast.success('Request recorded for ' + property.name + '.', {
        description: 'It moves to connected only when a reviewer confirms the account.',
      });
    } catch (err) {
      toast.error(errorMessage(err, 'Could not record the request'));
    }
  }

  return (
    <Card className="flex flex-col">
      <CardHeader>
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2">
            <Icon className="size-5 text-primary" />
            {property.name}
          </CardTitle>
          <CardDescription>
            <span className="font-mono text-xs">{property.host}</span> — {property.summary}
          </CardDescription>
        </div>
        <StatusBadge status={status} />
      </CardHeader>

      <CardContent className="flex flex-1 flex-col gap-4">
        {status === 'connected' && property.integration === 'record_only' && (
          <UnverifiableStatus property={property.name} />
        )}

        <div className="space-y-2">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            What connecting grants
          </p>
          <ul className="space-y-1.5">
            {property.grants.map((g) => (
              <li key={g} className="flex items-start gap-2 text-sm">
                <ShieldCheck className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
                <span>{g}</span>
              </li>
            ))}
          </ul>
        </div>

        <Note>{property.evidence}</Note>

        {property.key === 'str_domains' && <DomainLinks links={domainLinks} />}

        {connection && (
          <div className="grid gap-2 rounded-lg border border-border p-3 text-xs sm:grid-cols-2">
            <div>
              <span className="text-muted-foreground">{property.metadataLabel}: </span>
              <span className="font-mono">{recorded ?? '—'}</span>
            </div>
            <div>
              <span className="text-muted-foreground">Requested: </span>
              {connection.requested_at ? shortDate(connection.requested_at) : 'Never'}
            </div>
            <div>
              <span className="text-muted-foreground">Connected: </span>
              {connection.connected_at ? shortDate(connection.connected_at) : 'Not yet'}
            </div>
            <div>
              <span className="text-muted-foreground">Last changed: </span>
              {shortDate(connection.updated_at)}
            </div>
            {metadataString(connection.metadata, 'review_note') && (
              <p className="sm:col-span-2">
                <span className="text-muted-foreground">Reviewer note: </span>
                {metadataString(connection.metadata, 'review_note')}
              </p>
            )}
          </div>
        )}

        <div className="mt-auto space-y-3 pt-1">
          {canRequest && (
            <Field
              label={property.metadataLabel}
              htmlFor={inputId}
              hint={
                suggestions.length > 0
                  ? 'Stored in metadata. Suggested from what you already hold: ' +
                    suggestions.slice(0, 3).join(', ')
                  : 'Stored in the link record metadata, not in a column of its own. Optional.'
              }
            >
              <Input
                id={inputId}
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder={property.metadataLabel}
              />
            </Field>
          )}

          {canRequest ? (
            <Button className="w-full" disabled={request.isPending} onClick={() => void submit()}>
              {request.isPending ? <Loader2 className="animate-spin" /> : <Plug />}
              {status === 'rejected' ? 'Request again' : 'Request connection'}
            </Button>
          ) : (
            <p className="rounded-lg border border-dashed border-border p-3 text-xs text-muted-foreground">
              {!accountId
                ? 'A verified identity record is needed before a link can be requested.'
                : 'This link is ' +
                  status.replace(/_/g, ' ') +
                  '. A member may only change a link that is not connected or rejected, so there is nothing to send from here.'}
            </p>
          )}

          {/*
            Disconnect is the control this feature was asked for and cannot
            honestly provide. The own-UPDATE policy's USING clause admits only
            `not_connected` and `rejected` rows, and there is no DELETE policy
            at all, so both a "set to not_connected" update and a delete match
            zero rows and answer 200 with an empty body — no error to catch, and
            a success toast for an operation that did nothing. Confirmed against
            the local stack from every status. The full reasoning is stated once
            in the page footer rather than four times over.
          */}
          {/*
            Offered only from the two states a member may leave. The function
            refuses anything else, so this decides what to show — not what is
            allowed. `suspended` is absent on purpose: an administrator put the
            link there and only an administrator lifts it.
          */}
          {(status === 'connected' || status === 'requested') && (
            <Button
              variant="ghost"
              size="sm"
              className="w-full"
              disabled={setState.isPending}
              onClick={() =>
                setState.mutate(
                  { service: property.key, status: 'not_connected' },
                  {
                    onSuccess: () =>
                      toast.success(
                        status === 'connected'
                          ? `${property.name} link ended.`
                          : `Request to ${property.name} withdrawn.`
                      ),
                    onError: (e) =>
                      toast.error(e instanceof Error ? e.message : 'Could not change the link'),
                  }
                )
              }
            >
              {setState.isPending ? <Loader2 className="animate-spin" /> : <Unplug />}
              {status === 'connected' ? 'Disconnect this link' : 'Withdraw this request'}
            </Button>
          )}

          {property.internalPath && (
            <Button variant="ghost" size="sm" className="w-full" asChild>
              <Link to={property.internalPath}>
                Open {property.internalLabel} in IgniteHeX
                <ArrowUpRight />
              </Link>
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

/* -------------------------------------------------------------- the page */

export default function Connections() {
  const account = useIdentityAccount();
  const connections = useServiceConnections();
  const domainLinks = useDomainLinks();
  const owned = useOwnedDomains();

  const isLoading = account.isLoading || connections.isLoading;
  const isError = account.isError || connections.isError;

  function refetchAll() {
    void account.refetch();
    void connections.refetch();
    void domainLinks.refetch();
    void owned.refetch();
  }

  const header = (
    <PageHeader
      title="Connected accounts"
      description="One IgniteHeX identity, linked to your accounts on the sibling properties."
      actions={
        <Button
          variant="secondary"
          size="icon"
          aria-label="Refresh connection statuses"
          onClick={refetchAll}
          disabled={connections.isFetching}
        >
          <RefreshCw className={connections.isFetching ? 'animate-spin' : undefined} />
        </Button>
      }
    />
  );

  if (isLoading) {
    return (
      <>
        {header}
        <div className="space-y-6">
          <Skeleton className="h-40 w-full" />
          <div className="grid gap-6 lg:grid-cols-2">
            <Skeleton className="h-80 w-full" />
            <Skeleton className="h-80 w-full" />
          </div>
        </div>
      </>
    );
  }

  if (isError) {
    return (
      <>
        {header}
        <ErrorState error={account.error ?? connections.error} onRetry={refetchAll} />
      </>
    );
  }

  const rows = connections.data ?? [];
  const accountRecord = account.data ?? null;
  const byService = new Map(rows.map((r) => [r.service, r]));

  // A row whose service is not one of the four cards. Never dropped: a link
  // that exists and is invisible is worse than one that is merely unfamiliar.
  const other = rows.filter((r) => !PROPERTIES.some((p) => p.key === r.service));

  const domainSuggestions = (owned.data ?? []).map((d) => d.domain_name);
  const suggestionsFor = (key: string) => (key === 'str_domains' ? domainSuggestions : []);

  return (
    <>
      {header}

      <div className="space-y-6">
        {accountRecord ? (
          <IdentityPanel account={accountRecord} email={accountRecord.email} />
        ) : (
          <Card>
            <CardContent className="p-0">
              <EmptyState
                icon={<Fingerprint className="size-5" />}
                title="No verified identity record yet"
                description="A connection hangs off your account record, and you do not have one. Start it on the account screen — every link below needs it before it can be requested."
                action={
                  <Button asChild>
                    <Link to="/account">Go to your account</Link>
                  </Button>
                }
              />
            </CardContent>
          </Card>
        )}

        <div className="grid gap-6 lg:grid-cols-2">
          {PROPERTIES.map((p) => (
            <PropertyCard
              key={p.key}
              property={p}
              connection={byService.get(p.key) ?? null}
              accountId={accountRecord?.id ?? null}
              domainLinks={domainLinks.data ?? []}
              suggestions={suggestionsFor(p.key)}
            />
          ))}
        </div>

        {other.length > 0 && (
          <Card>
            <CardHeader>
              <div className="space-y-1">
                <CardTitle>Other links on this identity</CardTitle>
                <CardDescription>
                  Services the database allows that have no property card here —{' '}
                  {UNSURFACED_SERVICES.join(' and ').replace(/_/g, ' ')} are booking modes inside
                  CCoin Bank rather than separate properties. Shown so nothing held against your
                  identity is hidden from you.
                </CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0 pb-2">
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Service</TH>
                      <TH>Status</TH>
                      <TH>Reference</TH>
                      <TH>Last changed</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {other.map((r) => (
                      <TR key={r.id}>
                        <TD className="capitalize">{serviceName(r.service)}</TD>
                        <TD>
                          <StatusBadge status={r.status} />
                        </TD>
                        <TD className="font-mono text-xs">{r.external_reference ?? '—'}</TD>
                        <TD className="text-muted-foreground">{shortDate(r.updated_at)}</TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            </CardContent>
          </Card>
        )}

        <Card>
          <CardContent className="space-y-2">
            <Note>
              A status here is the state of a link record held by IgniteHeX. Nothing on this page
              contacts str.domains, strdome.com or ccoin.finance — a browser cannot reach them
              across origins and no function here proxies them — so no badge is a live health check
              of the property.
            </Note>
            <Note>
              Requesting a link never grants it. The database refuses a member who tries to write
              <span className="font-mono"> connected</span> outright, so the badge cannot run ahead
              of the decision even if this page had a bug.
            </Note>
            <Note>
              <strong className="font-medium text-foreground">Why disconnect is unavailable.</strong>{' '}
              A member cannot end their own link. The own-update policy on{' '}
              <span className="font-mono">v2_service_connections</span> only matches rows already at{' '}
              <span className="font-mono">not_connected</span> or{' '}
              <span className="font-mono">rejected</span>, and the table has no delete policy — so
              both routes affect zero rows and report no error, which is a success toast for an
              operation that did nothing. TODO(server): this needs either an RLS policy admitting
              connected → not_connected for the owner, or a disconnect routine that also tells the
              property the link has ended. The second is the right one: ending a link here while the
              far side still honours it is worse than not offering the button.
            </Note>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
