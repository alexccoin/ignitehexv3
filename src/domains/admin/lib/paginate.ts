/**
 * Paginated reads for full-table sweeps.
 *
 * PostgREST caps a response at 1,000 rows and says nothing about it: a plain
 * `select()` over a table with 4,000 rows returns 1,000 and a `200 OK`. v2's
 * exposure sweep would therefore have silently UNDERSTATED platform exposure
 * the moment any asset table crossed that line, which is precisely the number
 * you cannot afford to be quietly wrong about.
 *
 * v2 solved it per-caller in `src/lib/paginatedFetch.ts` with six near-identical
 * copies of the same while-loop, each `select('*')` and each returning `any[]`.
 * Here there is one loop, it keeps the caller's typed builder (so columns stay
 * explicit and rows stay typed), and it reports when it stopped early instead of
 * pretending it read everything.
 */

/** PostgREST's hard cap per response. */
export const PAGE_SIZE = 1000;

/** 40 pages = 40,000 rows per table. Beyond this the sweep belongs on the server. */
export const MAX_PAGES = 40;

/** The shape every supabase-js query resolves to, narrowed to what we need. */
export interface PageResponse<T> {
  data: T[] | null;
  error: { message: string } | null;
}

export interface PagedResult<T> {
  rows: T[];
  /**
   * True when the page budget ran out with a full page still coming back, i.e.
   * there is more data than was read. Every total derived from this result is a
   * lower bound and the UI must say so.
   */
  truncated: boolean;
}

/**
 * Read a table in pages until it runs out.
 *
 * `load` is called with an inclusive `[from, to]` range and must return the
 * caller's own typed query — that is what keeps the column list explicit and
 * the row type real rather than `any`.
 */
export async function paginate<T>(
  label: string,
  load: (from: number, to: number) => PromiseLike<PageResponse<T>>,
  maxPages: number = MAX_PAGES
): Promise<PagedResult<T>> {
  const rows: T[] = [];

  for (let page = 0; page < maxPages; page += 1) {
    const from = page * PAGE_SIZE;
    const { data, error } = await load(from, from + PAGE_SIZE - 1);

    // Errors are thrown with the table name attached: a sweep that quietly
    // skipped a table would report a smaller exposure than the truth.
    if (error) throw new Error(`${label}: ${error.message}`);
    if (!data || data.length === 0) return { rows, truncated: false };

    rows.push(...data);

    // A short page is the end of the table. A full page means there may be more.
    if (data.length < PAGE_SIZE) return { rows, truncated: false };
  }

  return { rows, truncated: true };
}
