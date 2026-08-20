import { supabase } from '@/lib/supabase';

/**
 * Did the sweep read the whole table, or only the part RLS let it see?
 *
 * THE DEFECT THIS EXISTS FOR (F-034)
 *
 * `user_staking_pools` had no admin SELECT policy on the self-hosted stack, so
 * `/admin`, signed in as an administrator, read 9 of the 108 rows in it — the
 * admin's own. Postgres does not report that. RLS is a filter, not a
 * permission error: an authorised SELECT over rows you may not see returns
 * `HTTP 200 []`. So `sweep()` saw an empty result, recorded no error, and every
 * "platform-wide" staking figure on the risk console was one member's.
 *
 * `truncatedTables` could never have caught it. That flag means "the page
 * budget ran out", which is a different way to be short and the only one the
 * client could previously detect. **A sweep that cannot tell "no rows" from
 * "not allowed to see rows" is the defect; the missing policy was just the
 * instance of it that got noticed.** It got noticed by accident, because
 * 81,304 staked DOMAIN tokens failed to appear in an unrelated list.
 *
 * HOW IT IS DETECTED
 *
 * `admin_sweep_row_counts` is SECURITY DEFINER, so its counts are not filtered
 * by the caller's RLS, and it is gated on `is_admin(auth.uid())` with the
 * table names intersected against a fixed allow-list server-side. Comparing
 * what the sweep received against what the table holds turns an invisible
 * short read into a number on screen.
 *
 * WHAT THIS REQUIRES OF THE SWEEPS
 *
 * Every sweep must read its table WHOLE and narrow in the fold. A server-side
 * `.eq(...)` on a swept query makes the read legitimately smaller than the
 * table and this check would call it a short read. There is one such
 * temptation in platformExposure (`marketplace_escrow_balances`, where only
 * `locked` rows count) and it filters client-side for exactly this reason.
 *
 * WHAT A SHORT READ IS NOT
 *
 * It is not necessarily a bug in the sweep. Four tables in PRODUCTION —
 * `arss_token_purchases`, `crypto_orders`, `user_wallets` and
 * `withdrawal_requests` — carry a "view your own" SELECT policy and no admin
 * read policy at all, so an administrator is *by policy* not entitled to see
 * them whole. That is a decision someone may have made on purpose. The point
 * is that the console must say so rather than print a total that silently
 * omits them.
 */

/** One table's read coverage. */
export interface TableCoverage {
  table: string;
  /** Rows the sweep actually received. */
  read: number;
  /** Rows the table holds, or null when the count could not be obtained. */
  total: number | null;
}

export interface CoverageReport {
  /** Every swept table, with what was read and what exists. */
  tables: TableCoverage[];
  /** Tables where fewer rows came back than the table holds. */
  short: TableCoverage[];
  /** Rows the sweep did not see, summed over `short`. */
  missedRows: number;
  /**
   * Tables whose true size could not be established — the counts RPC did not
   * cover them, or did not answer at all. Not evidence that they are complete.
   */
  unverified: string[];
  /** Whether the counts RPC answered. False means coverage is unknown, not fine. */
  verified: boolean;
  /** Why the counts RPC failed, when it did. */
  error: string | null;
}

interface CountRow {
  table_name: string;
  total_rows: number | string;
}

const EMPTY: CoverageReport = {
  tables: [],
  short: [],
  missedRows: 0,
  unverified: [],
  verified: false,
  error: null,
};

/**
 * Compare a sweep's per-table row counts against the authoritative ones.
 *
 * `read` maps table name to the number of rows the sweep received. A table
 * missing from the RPC's answer is reported as `unverified` rather than
 * assumed complete — "we could not check" and "we checked and it was fine"
 * are the two states this whole module exists to keep apart.
 *
 * Never throws. A failed coverage check must not take down the exposure figure
 * it annotates; it downgrades to `verified: false`, which the UI states.
 */
export async function checkCoverage(read: Record<string, number>): Promise<CoverageReport> {
  const wanted = Object.keys(read).sort();
  if (wanted.length === 0) return EMPTY;

  // Bound to `supabase`, not extracted from it. `const rpc = supabase.rpc`
  // loses `this` and throws "Cannot read properties of undefined (reading
  // 'rest')" at call time, which this module would then have reported as
  // "coverage could not be checked" — a coverage checker that silently fails
  // to check coverage is the same class of defect it exists to catch.
  //
  // Hand-typed because src/lib/database.types.ts is generated from the schema
  // as it stood before 20260819140100 and does not carry this function.
  const rpc = supabase.rpc.bind(supabase) as unknown as (
    fn: string,
    args: Record<string, unknown>
  ) => PromiseLike<{ data: CountRow[] | null; error: { message: string } | null }>;

  let data: CountRow[] | null = null;
  let error: { message: string } | null = null;

  try {
    ({ data, error } = await rpc('admin_sweep_row_counts', { p_tables: wanted }));
  } catch (thrown) {
    error = { message: thrown instanceof Error ? thrown.message : String(thrown) };
  }

  if (error || !data) {
    return {
      ...EMPTY,
      unverified: wanted,
      error: error?.message ?? 'admin_sweep_row_counts returned nothing',
    };
  }

  const totals = new Map<string, number>();
  for (const row of data) {
    const n = Number(row.total_rows);
    if (Number.isFinite(n)) totals.set(row.table_name, n);
  }

  const tables: TableCoverage[] = wanted.map((table) => ({
    table,
    read: read[table] ?? 0,
    total: totals.has(table) ? (totals.get(table) as number) : null,
  }));

  const short = tables.filter((t) => t.total !== null && t.read < t.total);
  const unverified = tables.filter((t) => t.total === null).map((t) => t.table);

  return {
    tables,
    short,
    missedRows: short.reduce((sum, t) => sum + ((t.total ?? 0) - t.read), 0),
    unverified,
    verified: true,
    error: null,
  };
}
