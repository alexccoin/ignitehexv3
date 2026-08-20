import { useState } from 'react';
import { toast } from 'sonner';
import {
  AlertTriangle,
  Bell,
  BellOff,
  Check,
  Droplets,
  Loader2,
  Shield,
  SlidersHorizontal,
  TrendingDown,
  TrendingUp,
} from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState, ErrorState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, percent, relativeTime } from '@/lib/format';
import { cn } from '@/lib/utils';
import { Detail, LockedAction, SeverityBadge } from './shared';
import { useDecideAlert, useFlashAlerts, useMarginSettings, type FlashAlert } from './hooks';

const ALERT_ICONS: Record<string, typeof Bell> = {
  crash_warning: AlertTriangle,
  flash_sell: TrendingDown,
  flash_buy: TrendingUp,
  margin_breach: Shield,
  liquidity_warning: Droplets,
};

const FILTERS = [
  { id: 'open', label: 'Open' },
  { id: 'all', label: 'All' },
] as const;

type Filter = (typeof FILTERS)[number]['id'];

const isOpen = (alert: FlashAlert) => alert.status === 'active' || alert.status === 'acknowledged';

/**
 * Market alerts and the margin policy they are measured against.
 *
 * Two kinds of write live on this screen and they are treated differently on
 * purpose. Acknowledging or resolving an alert is a note on a log line: nothing
 * moves, the operator policy on the table permits it, and it is done here as a
 * checked update that verifies a row actually came back — because PostgREST
 * reports an update RLS filtered to nothing as a success, which is how v2's
 * console showed "resolved" on alerts it had not touched.
 *
 * Changing a margin setting is the other kind. Those thresholds drive automatic
 * buys and sells, so writing one from a browser is writing a trading
 * instruction from a browser. The controls are disabled and the table is shown
 * read-only until there is a server-side routine to accept the change.
 */
export default function Alerts() {
  const alerts = useFlashAlerts();
  const margins = useMarginSettings();
  const decide = useDecideAlert();
  const [filter, setFilter] = useState<Filter>('open');

  const all = alerts.data ?? [];
  const shown = filter === 'open' ? all.filter(isOpen) : all;
  const critical = all.filter((a) => isOpen(a) && a.severity.toLowerCase() === 'critical');

  const act = (alert: FlashAlert, status: 'acknowledged' | 'resolved') => {
    decide.mutate(
      { alertId: alert.id, status },
      {
        onSuccess: () =>
          toast.success(status === 'resolved' ? 'Alert resolved.' : 'Alert acknowledged.'),
        onError: (error: Error) => toast.error(error.message),
      }
    );
  };

  return (
    <>
      <PageHeader
        title="Alerts"
        description="Market conditions the vault is watching, and the margin policy behind them."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <Stat
          label="Open alerts"
          value={String(all.filter(isOpen).length)}
          sub="Active or acknowledged"
          tone={all.some(isOpen) ? 'warning' : 'default'}
          icon={<Bell className="size-4" />}
          loading={alerts.isLoading}
        />
        <Stat
          label="Critical"
          value={String(critical.length)}
          sub="Highest severity, still open"
          tone={critical.length > 0 ? 'danger' : 'success'}
          icon={<AlertTriangle className="size-4" />}
          loading={alerts.isLoading}
        />
        <Stat
          label="Margin rules"
          value={String((margins.data ?? []).filter((m) => m.is_active).length)}
          sub={`${(margins.data ?? []).length} configured in total`}
          icon={<SlidersHorizontal className="size-4" />}
          loading={margins.isLoading}
        />
      </div>

      <Card className="mb-6">
        <CardHeader>
          <div>
            <CardTitle>Market alerts</CardTitle>
            <CardDescription>Newest first, capped at the last fifty.</CardDescription>
          </div>
          <div className="flex gap-1.5">
            {FILTERS.map((f) => (
              <Button
                key={f.id}
                size="sm"
                variant={filter === f.id ? 'primary' : 'ghost'}
                onClick={() => setFilter(f.id)}
              >
                {f.label}
              </Button>
            ))}
          </div>
        </CardHeader>
        <CardContent className="space-y-3 pt-3">
          {alerts.isLoading ? (
            <>
              <Skeleton className="h-24 w-full" />
              <Skeleton className="h-24 w-full" />
            </>
          ) : alerts.isError ? (
            <ErrorState
              title="Could not load alerts"
              error={alerts.error}
              onRetry={() => void alerts.refetch()}
            />
          ) : shown.length === 0 ? (
            <EmptyState
              icon={<BellOff className="size-5" />}
              title={filter === 'open' ? 'No open alerts' : 'No alerts recorded'}
              description={
                filter === 'open'
                  ? 'Nothing is currently active or waiting on a decision.'
                  : 'No market alert has been raised for this vault.'
              }
            />
          ) : (
            shown.map((alert) => {
              const Icon = ALERT_ICONS[alert.alert_type] ?? Bell;
              const busy = decide.isPending && decide.variables?.alertId === alert.id;
              const criticalRow = alert.severity.toLowerCase() === 'critical' && isOpen(alert);

              return (
                <article
                  key={alert.id}
                  className={cn(
                    'rounded-lg border border-border p-4',
                    criticalRow && 'border-danger/40 bg-danger/5'
                  )}
                >
                  <div className="flex items-start gap-3">
                    <span
                      className={cn(
                        'mt-0.5 shrink-0',
                        criticalRow ? 'text-danger' : 'text-muted-foreground'
                      )}
                    >
                      <Icon className="size-5" aria-hidden="true" />
                    </span>
                    <div className="min-w-0 flex-1 space-y-2">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-medium">{alert.title}</p>
                        <Badge tone="neutral">{alert.asset_symbol}</Badge>
                        <SeverityBadge severity={alert.severity} />
                        <StatusBadge status={alert.status} />
                      </div>

                      {alert.description && (
                        <p className="text-sm text-muted-foreground">{alert.description}</p>
                      )}

                      <div className="flex flex-wrap gap-x-8 gap-y-2">
                        <Detail
                          label="Trigger"
                          value={
                            alert.trigger_price === null
                              ? '—'
                              : money(Number(alert.trigger_price), 'USD')
                          }
                        />
                        <Detail
                          label="Market"
                          value={
                            alert.market_price === null
                              ? '—'
                              : money(Number(alert.market_price), 'USD')
                          }
                        />
                        <Detail label="Raised" value={relativeTime(alert.created_at)} />
                        {alert.action_taken && (
                          <Detail label="Action taken" value={alert.action_taken} />
                        )}
                      </div>

                      {isOpen(alert) && (
                        <div className="flex flex-wrap gap-2 pt-1">
                          {alert.status === 'active' && (
                            <Button
                              size="sm"
                              variant="secondary"
                              disabled={busy}
                              onClick={() => act(alert, 'acknowledged')}
                            >
                              {busy ? <Loader2 className="animate-spin" /> : <Check />}
                              Acknowledge
                            </Button>
                          )}
                          <Button
                            size="sm"
                            variant="secondary"
                            disabled={busy}
                            onClick={() => act(alert, 'resolved')}
                          >
                            {busy ? <Loader2 className="animate-spin" /> : <Check />}
                            Resolve
                          </Button>
                        </div>
                      )}
                    </div>
                  </div>
                </article>
              );
            })
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Margin policy</CardTitle>
            <CardDescription>
              The thresholds automatic buys and sells are measured against. Read-only here.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4 pt-3">
          {margins.isLoading ? (
            <div className="space-y-2">
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-10 w-full" />
            </div>
          ) : margins.isError ? (
            <ErrorState error={margins.error} onRetry={() => void margins.refetch()} />
          ) : (margins.data ?? []).length === 0 ? (
            <EmptyState
              icon={<SlidersHorizontal className="size-5" />}
              title="No margin rules configured"
              description="Nothing has been recorded in guardian_margin_settings."
            />
          ) : (
            <TableWrap>
              <Table>
                <THead>
                  <TR>
                    <TH>Asset</TH>
                    <TH className="text-right">Margin</TH>
                    <TH className="text-right">Auto-buy below</TH>
                    <TH className="text-right">Auto-sell above</TH>
                    <TH>Markets</TH>
                    <TH>State</TH>
                  </TR>
                </THead>
                <TBody>
                  {(margins.data ?? []).map((m) => (
                    <TR key={m.id}>
                      <TD className="font-medium">{m.asset_symbol}</TD>
                      <TD className="tabular text-right">{percent(Number(m.margin_percent), 2)}</TD>
                      <TD className="tabular text-right">
                        {m.auto_buy_threshold === null
                          ? '—'
                          : money(Number(m.auto_buy_threshold), 'USD')}
                      </TD>
                      <TD className="tabular text-right">
                        {m.auto_sell_threshold === null
                          ? '—'
                          : money(Number(m.auto_sell_threshold), 'USD')}
                      </TD>
                      <TD className="text-muted-foreground">
                        {(m.target_markets ?? []).length > 0
                          ? (m.target_markets ?? []).join(', ')
                          : 'All'}
                      </TD>
                      <TD>
                        <Badge tone={m.is_active ? 'success' : 'neutral'}>
                          {m.is_active ? 'Active' : 'Paused'}
                        </Badge>
                      </TD>
                    </TR>
                  ))}
                </TBody>
              </Table>
            </TableWrap>
          )}

          {/*
            TODO(server): changing a margin rule needs a `guardian-set-margin`
            edge function that validates the band, records who changed it from
            the JWT rather than from a client-supplied field, and versions the
            previous rule so an automated sell can be traced to the policy that
            authorised it. v2 inserted a new guardian_margin_settings row
            straight from the admin page with `set_by` taken from
            `auth.getUser()` in the browser, and never checked the result.
          */}
          <LockedAction
            icon={<SlidersHorizontal aria-hidden="true" />}
            label="Change margin policy"
            reason="These thresholds trigger automated buys and sells. A trading instruction is accepted by the server, validated against its own band, and attributed to the caller's token — not written from a form."
          />
        </CardContent>
      </Card>
    </>
  );
}
