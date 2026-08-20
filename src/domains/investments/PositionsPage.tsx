import { Server, Landmark, Hourglass } from 'lucide-react';
import { PageHeader } from '@/components/layout/AppShell';
import { Badge } from '@/components/ui/badge';
import { StatusBadge } from '@/components/ui/status';
import { Skeleton } from '@/components/ui/skeleton';
import { Stat } from '@/components/ui/stat';
import { EmptyState } from '@/components/ui/states';
import { TableWrap, Table, THead, TBody, TR, TH, TD } from '@/components/ui/table';
import { money, percent, shortDate, token } from '@/lib/format';
import {
  CCOS_MINT_BAND,
  FOUNDER_LOCK_DAYS,
  FOUNDER_POSITION_MAX_USD,
  FOUNDER_POSITION_SLOTS,
  founderPoolMeta,
} from './constants';
import { Async, Detail, LockedAction, Section } from './shared';
import { useFounderPortfolio, useShareHoldings, useStarwHoldings } from './hooks';

/**
 * What the member actually holds: shares, vesting tokens, founder positions
 * and nodes.
 *
 * Everything here is read-only. The two things v2 let the browser do on these
 * screens — crediting a founder pool and marking a withdrawal executed — are
 * the two operations that most need to be atomic and on-chain-verified, so
 * both are rendered disabled with the endpoint they are waiting on.
 */
export default function PositionsPage() {
  const holdings = useShareHoldings();
  const starw = useStarwHoldings();

  const shares = holdings.data?.shares;
  const vesting = holdings.data?.vesting ?? [];
  const stillVesting = vesting.filter((v) => v.status !== 'released');
  const nodeCount = (starw.data?.nodes.length ?? 0) + (starw.data?.supernodes.length ?? 0);
  const rewardTotal = (starw.data?.rewards ?? []).reduce(
    (sum, r) => sum + Number(r.reward_amount ?? 0),
    0
  );

  return (
    <>
      <PageHeader
        title="Positions"
        description="Shares, vesting tokens, founder positions and node assignments."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="Shares"
          value={Number(shares?.balance ?? 0).toLocaleString('en-IE')}
          sub={`${Number(shares?.wnft_shares ?? 0).toLocaleString('en-IE')} as wNFT`}
          loading={holdings.isLoading}
          icon={<Landmark className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Locked shares"
          value={Number(shares?.locked_balance ?? 0).toLocaleString('en-IE')}
          sub={shares?.vesting_end_date ? `Until ${shortDate(shares.vesting_end_date)}` : 'None'}
          loading={holdings.isLoading}
          tone={Number(shares?.locked_balance ?? 0) > 0 ? 'warning' : 'default'}
        />
        <Stat
          label="Vesting positions"
          value={String(stillVesting.length)}
          loading={holdings.isLoading}
          icon={<Hourglass className="size-4" aria-hidden="true" />}
        />
        <Stat
          label="Nodes"
          value={String(nodeCount)}
          sub={`${token(rewardTotal, 'wstr')} rewarded`}
          loading={starw.isLoading}
          icon={<Server className="size-4" aria-hidden="true" />}
        />
      </div>

      <div className="space-y-6">
        <Section
          title="Vesting"
          description="Tokens held back until their release date."
          bodyClassName="p-0 pt-0"
        >
          <Async
            query={holdings}
            isEmpty={(d) => d.vesting.length === 0}
            emptyTitle="Nothing vesting"
            emptyDescription="You hold no tokens under a vesting schedule."
            skeleton={
              <div className="p-5">
                <Skeleton className="h-24 w-full" />
              </div>
            }
          >
            {(data) => (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Token</TH>
                      <TH className="text-right">Amount</TH>
                      <TH>Source</TH>
                      <TH>Starts</TH>
                      <TH>Releases</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {data.vesting.map((v) => (
                      <TR key={v.id}>
                        <TD className="font-medium uppercase">{v.token_type}</TD>
                        <TD className="tabular text-right">{token(v.amount, v.token_type)}</TD>
                        <TD className="text-muted-foreground">
                          {v.source.replace(/_/g, ' ')} · {v.vesting_months}m
                        </TD>
                        <TD className="text-muted-foreground">{shortDate(v.vesting_start_date)}</TD>
                        <TD className="text-muted-foreground">{shortDate(v.vesting_end_date)}</TD>
                        <TD>
                          <StatusBadge status={v.status} />
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}
          </Async>
        </Section>

        <FounderSection />
        <NodesSection />
      </div>
    </>
  );
}

/* ---------------------------------------------------------- founder pool */

function FounderSection() {
  const founder = useFounderPortfolio();

  return (
    <Section
      title="Founder pool"
      description={`Positions are capped at ${money(FOUNDER_POSITION_MAX_USD, 'USD')} and locked for ${FOUNDER_LOCK_DAYS} days.`}
    >
      <Async
        query={founder}
        skeleton={<Skeleton className="h-40 w-full" />}
        isEmpty={(d) => !d.hasAccess}
        emptyTitle="No founder access"
        emptyDescription="Founder pool access is granted on the server and enforced by row-level security. If you should have it, ask an administrator to grant it."
      >
        {(data) => (
          <div className="space-y-6">
            {data.pools.length === 0 ? (
              <EmptyState
                title="No pools"
                description="Your founder pools have not been created yet."
              />
            ) : (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Pool</TH>
                      <TH className="text-right">Balance</TH>
                      <TH className="text-right">Value</TH>
                      <TH className="text-right">Last price</TH>
                      <TH>Updated</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {data.pools.map((pool) => {
                      const meta = founderPoolMeta(pool.pool_type);
                      return (
                        <TR key={pool.id}>
                          <TD className="font-medium">
                            {meta.name}
                            <span className="ml-2 text-xs text-muted-foreground">{meta.symbol}</span>
                          </TD>
                          <TD className="tabular text-right">
                            {token(pool.balance, meta.symbol)}
                          </TD>
                          <TD className="tabular text-right">{money(pool.usd_value, 'USD')}</TD>
                          <TD className="tabular text-right text-muted-foreground">
                            {money(pool.last_price, 'USD')}
                          </TD>
                          <TD className="text-muted-foreground">{shortDate(pool.updated_at)}</TD>
                        </TR>
                      );
                    })}
                  </TBody>
                </Table>
              </TableWrap>
            )}

            {/* TODO(server): needs a founder-pool-deposit edge function that,
                in one transaction, records the deposit, applies the balance as
                a relative update, calls calculate_ccos_mint and credits the
                CCOS pool. v2 did all four from the browser: two separate
                read-modify-writes against a stale in-memory pools array
                (FounderPool.tsx:394-432), so two deposits arriving together
                lost one. A matching founder-pool-withdraw is needed for the
                other direction. */}
            <LockedAction
              label="Deposit"
              reason="Deposits, and the CCOS mint that follows them, are applied by the server in one transaction so concurrent deposits cannot overwrite each other."
            />

            <div className="border-t border-border pt-4">
              <h4 className="mb-3 text-sm font-medium">
                Positions
                <span className="ml-2 font-normal text-muted-foreground">
                  {data.positions.length} of {FOUNDER_POSITION_SLOTS} slots
                </span>
              </h4>
              {data.positions.length === 0 ? (
                <EmptyState title="No positions" description="You hold no founder position." />
              ) : (
                <div className="grid gap-4 lg:grid-cols-2">
                  {data.positions.map((p) => {
                    const used = Number(p.current_usd_value ?? 0);
                    const cap = Number(p.max_usd_limit ?? FOUNDER_POSITION_MAX_USD);
                    const utilisation = cap > 0 ? Math.min((used / cap) * 100, 100) : 0;
                    const unlocked =
                      !!p.withdrawal_available_date &&
                      new Date(p.withdrawal_available_date) <= new Date();

                    return (
                      <div key={p.id} className="rounded-lg border border-border p-4">
                        <div className="mb-3 flex items-start justify-between gap-3">
                          <div>
                            <p className="font-medium">
                              {p.title ?? 'Founder position'} #{p.position_number}
                            </p>
                            <p className="text-xs text-muted-foreground">
                              Minimum {money(p.min_deposit_usd, 'USD')}
                            </p>
                          </div>
                          <div className="flex shrink-0 gap-2">
                            {p.is_prime && <Badge tone="primary">Prime</Badge>}
                            <StatusBadge status={p.status} />
                          </div>
                        </div>

                        <div className="grid grid-cols-2 gap-3">
                          <Detail label="Committed" value={money(used, 'USD')} />
                          <Detail label="Capacity" value={money(cap, 'USD')} />
                          <Detail label="Utilisation" value={percent(utilisation, 1)} />
                          <Detail
                            label="CCOS mint"
                            value={
                              p.ccos_mint_percentage === null
                                ? '—'
                                : percent(p.ccos_mint_percentage, 2)
                            }
                          />
                          <Detail
                            label="BTC in"
                            value={p.input_btc_amount ? token(p.input_btc_amount, 'BTC') : '—'}
                          />
                          <Detail
                            label="BTC out"
                            value={p.output_btc_amount ? token(p.output_btc_amount, 'BTC') : '—'}
                          />
                        </div>

                        <div className="mt-3" aria-hidden="true">
                          <div className="h-1.5 w-full overflow-hidden rounded-full bg-elevated">
                            <div
                              className="h-full rounded-full bg-primary"
                              style={{ width: `${utilisation}%` }}
                            />
                          </div>
                        </div>

                        <p className="mt-3 text-xs text-muted-foreground">
                          {p.withdrawal_executed
                            ? 'Withdrawal already executed.'
                            : unlocked
                              ? 'Lock period has ended.'
                              : `Locked until ${shortDate(p.withdrawal_available_date)}.`}
                        </p>

                        {/* TODO(server): needs an execute-founder-withdrawal edge
                            function. It has to re-check is_withdrawal_available,
                            broadcast the payout and store the hash the chain
                            actually returns. v2's withdraw button had no handler
                            at all, while its deposit path wrote a transaction_hash
                            built from Math.random() and marked the row
                            'completed' (FounderPool.tsx:406-421). A reference
                            that is not a real transaction is worse than none. */}
                        {!p.withdrawal_executed && unlocked && (
                          <LockedAction
                            className="mt-3"
                            label="Withdraw"
                            reason="A withdrawal is broadcast by the server and recorded with the hash the chain returns; no reference is ever generated locally."
                          />
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            <div className="border-t border-border pt-4">
              <h4 className="mb-3 text-sm font-medium">Pool ledger</h4>
              {data.transactions.length === 0 ? (
                <EmptyState title="No movements" description="Nothing has moved in your pools." />
              ) : (
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Date</TH>
                        <TH>Pool</TH>
                        <TH>Type</TH>
                        <TH className="text-right">Amount</TH>
                        <TH className="text-right">CCOS minted</TH>
                        <TH>Reference</TH>
                        <TH>Status</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {data.transactions.map((t) => {
                        const meta = founderPoolMeta(t.pool_type);
                        const mint = Number(t.mint_percentage ?? 0);
                        const inBand = mint >= CCOS_MINT_BAND.min && mint <= CCOS_MINT_BAND.max;
                        return (
                          <TR key={t.id}>
                            <TD className="text-muted-foreground">{shortDate(t.created_at)}</TD>
                            <TD className="font-medium">{meta.name}</TD>
                            <TD className="capitalize text-muted-foreground">
                              {t.transaction_type}
                            </TD>
                            <TD className="tabular text-right">
                              {token(t.amount, meta.symbol)}
                              <span className="ml-2 text-xs text-muted-foreground">
                                {money(t.usd_value_at_time, 'USD')}
                              </span>
                            </TD>
                            <TD className="tabular text-right">
                              {t.ccos_minted === null ? (
                                '—'
                              ) : (
                                <>
                                  {token(t.ccos_minted, 'ccos')}
                                  {t.mint_percentage !== null && (
                                    <Badge tone={inBand ? 'neutral' : 'warning'} className="ml-2">
                                      {percent(mint, 1)}
                                    </Badge>
                                  )}
                                </>
                              )}
                            </TD>
                            <TD className="tabular max-w-40 truncate text-xs text-muted-foreground">
                              {/* An empty hash is shown as such. v2 filled this
                                  column with a locally generated string, so a
                                  transfer that had never been broadcast read as
                                  confirmed. */}
                              {t.transaction_hash ?? 'Not settled on-chain'}
                            </TD>
                            <TD>
                              <StatusBadge status={t.status} />
                            </TD>
                          </TR>
                        );
                      })}
                    </TBody>
                  </Table>
                </TableWrap>
              )}
            </div>
          </div>
        )}
      </Async>
    </Section>
  );
}

/* ----------------------------------------------------------------- nodes */

function NodesSection() {
  const starw = useStarwHoldings();

  return (
    <Section
      title="Nodes"
      description="StarW nodes, supernodes and the wSTR they have paid out."
    >
      <Async
        query={starw}
        skeleton={<Skeleton className="h-32 w-full" />}
        isEmpty={(d) =>
          d.nodes.length === 0 && d.supernodes.length === 0 && d.purchases.length === 0
        }
        emptyTitle="No nodes"
        emptyDescription="You hold no StarW nodes or supernodes."
      >
        {(data) => (
          <div className="space-y-6">
            {(data.nodes.length > 0 || data.supernodes.length > 0) && (
              <TableWrap>
                <Table>
                  <THead>
                    <TR>
                      <TH>Kind</TH>
                      <TH className="text-right">Node</TH>
                      <TH className="text-right">Workers</TH>
                      <TH>Assigned</TH>
                      <TH>Status</TH>
                    </TR>
                  </THead>
                  <TBody>
                    {[
                      ...data.nodes.map((n) => ({ kind: 'StarW node', ...n })),
                      ...data.supernodes.map((n) => ({ kind: 'Supernode', ...n })),
                    ].map((n) => (
                      <TR key={`${n.kind}-${n.id}`}>
                        <TD className="font-medium">{n.kind}</TD>
                        <TD className="tabular text-right">#{n.node_number}</TD>
                        <TD className="tabular text-right">{n.worker_nodes_count}</TD>
                        <TD className="text-muted-foreground">{shortDate(n.assigned_at)}</TD>
                        <TD>
                          <StatusBadge status={n.status} />
                        </TD>
                      </TR>
                    ))}
                  </TBody>
                </Table>
              </TableWrap>
            )}

            {data.purchases.length > 0 && (
              <div className="border-t border-border pt-4">
                <h4 className="mb-3 text-sm font-medium">Node orders</h4>
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Ordered</TH>
                        <TH className="text-right">Nodes</TH>
                        <TH className="text-right">Cost</TH>
                        <TH>ARSS bonus</TH>
                        <TH>Status</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {data.purchases.map((p) => (
                        <TR key={p.id}>
                          <TD className="text-muted-foreground">{shortDate(p.created_at)}</TD>
                          <TD className="tabular text-right">{p.node_count}</TD>
                          <TD className="tabular text-right">{money(p.total_cost, 'USD')}</TD>
                          <TD className="text-muted-foreground">{p.arss_bonus ?? '—'}</TD>
                          <TD>
                            <StatusBadge status={p.status} />
                          </TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              </div>
            )}

            {/* TODO(server): needs a submit-starw-purchase edge function. The
                order has to be priced server-side and the payment confirmed
                before a node is assigned; v2 wrote the crypto amount straight
                from a CoinGecko quote in the browser, with no guard against a
                zero price, so an order could be stored as NaN nodes' worth. */}
            <LockedAction
              label="Order nodes"
              reason="Node orders are priced and settled server-side before a node number is assigned."
            />

            {data.rewards.length > 0 && (
              <div className="border-t border-border pt-4">
                <h4 className="mb-3 text-sm font-medium">Recent wSTR rewards</h4>
                <TableWrap>
                  <Table>
                    <THead>
                      <TR>
                        <TH>Date</TH>
                        <TH className="text-right">Amount</TH>
                        <TH>Status</TH>
                      </TR>
                    </THead>
                    <TBody>
                      {data.rewards.map((r) => (
                        <TR key={r.id}>
                          <TD className="text-muted-foreground">{shortDate(r.reward_date)}</TD>
                          <TD className="tabular text-right">{token(r.reward_amount, 'wstr')}</TD>
                          <TD>
                            <StatusBadge status={r.status} />
                          </TD>
                        </TR>
                      ))}
                    </TBody>
                  </Table>
                </TableWrap>
              </div>
            )}
          </div>
        )}
      </Async>
    </Section>
  );
}
