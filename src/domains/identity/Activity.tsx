import { History, ScrollText } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { StatusBadge } from '@/components/ui/status';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { relativeTime, shortDate } from '@/lib/format';
import { AsyncSection, Note } from './shared';
import { connectionEvents, useConnectionAudit, useServiceConnections } from './hooks';

/**
 * Connection history, from what the rows actually remember.
 *
 * There is no transition log for `v2_service_connections`. The table carries
 * one trigger and it only touches `updated_at`; `v2_admin_actions` — the
 * platform's decision log, which a member may read their own rows of — has an
 * insert path for accounts and claims but none for connections, and no client
 * role can write it (a member INSERT answers 42501).
 *
 * So this page reports the four timestamps each row carries, each of which is
 * evidence of a specific transition, and says out loud what it cannot tell you:
 * a rejection followed by a fresh request leaves one `requested_at`, so the
 * rejection is not in this list. That is a gap in the schema, not something to
 * paper over with a plausible-looking timeline.
 */
export default function Activity() {
  const connections = useServiceConnections();
  const audit = useConnectionAudit();

  const events = connectionEvents(connections.data ?? []);
  const eventsQuery = { ...connections, data: connections.data ? events : undefined };

  return (
    <>
      <PageHeader
        title="Connection activity"
        description="What has happened to the links between your IgniteHeX identity and the sibling properties."
      />

      <div className="space-y-6">
        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <History className="size-5 text-primary" />
                Observed transitions
              </CardTitle>
              <CardDescription>
                Read from the timestamps on each link record. Newest first.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 p-0 pb-5">
            <AsyncSection
              query={eventsQuery}
              emptyTitle="Nothing has happened yet"
              emptyDescription="Once you request a link to a property, every step it takes appears here."
              emptyIcon={<History className="size-5" />}
              skeletonClassName="mx-5 h-48"
            >
              {(rows) => (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>When</TH>
                        <TH>Property</TH>
                        <TH>Event</TH>
                        <TH>Detail</TH>
                        <TH>Status now</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((e) => (
                        <TR key={e.id}>
                          <TD className="whitespace-nowrap">
                            <p className="text-sm">{shortDate(e.at)}</p>
                            <p className="text-xs text-muted-foreground">{relativeTime(e.at)}</p>
                          </TD>
                          <TD className="font-medium">{e.serviceLabel}</TD>
                          <TD>{e.label}</TD>
                          <TD className="max-w-[22rem] text-xs text-muted-foreground">
                            {e.detail ?? '—'}
                          </TD>
                          <TD>
                            <StatusBadge status={e.status} />
                          </TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              )}
            </AsyncSection>

            <div className="space-y-2 px-5">
              <Note>
                Each line is a timestamp on a link record —{' '}
                <span className="font-mono">created_at</span>,{' '}
                <span className="font-mono">requested_at</span>,{' '}
                <span className="font-mono">connected_at</span> and{' '}
                <span className="font-mono">updated_at</span>. Nothing between them is inferred.
              </Note>
              <Note>
                A row only keeps one of each. If a request was rejected and then raised again, the
                rejection is not shown here — the row overwrote the timestamp that would have proved
                it. Recording transitions needs a trigger on{' '}
                <span className="font-mono">v2_service_connections</span> writing to{' '}
                <span className="font-mono">v2_admin_actions</span>, the way{' '}
                <span className="font-mono">v2_accounts</span> already does.
              </Note>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="space-y-1">
              <CardTitle className="flex items-center gap-2">
                <ScrollText className="size-5 text-primary" />
                Recorded decisions
              </CardTitle>
              <CardDescription>
                Entries in the platform decision log that name one of your links.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 p-0 pb-5">
            <AsyncSection
              query={audit}
              emptyTitle="No decisions are logged"
              emptyDescription="Expected: no trigger writes connection decisions to v2_admin_actions yet, so this panel stays empty until one exists. It is queried rather than hidden so it fills in on its own the day that changes."
              emptyIcon={<ScrollText className="size-5" />}
              skeletonClassName="mx-5 h-32"
            >
              {(rows) => (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>When</TH>
                        <TH>Action</TH>
                        <TH>From</TH>
                        <TH>To</TH>
                        <TH>Notes</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {rows.map((r) => (
                        <TR key={r.id}>
                          <TD className="whitespace-nowrap">{shortDate(r.created_at)}</TD>
                          <TD>{r.action}</TD>
                          <TD>
                            <StatusBadge status={r.from_status ?? 'unknown'} />
                          </TD>
                          <TD>
                            <StatusBadge status={r.to_status ?? 'unknown'} />
                          </TD>
                          <TD className="max-w-[22rem] text-xs text-muted-foreground">
                            {r.notes ?? '—'}
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
      </div>
    </>
  );
}
