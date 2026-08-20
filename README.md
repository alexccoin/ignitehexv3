# IgniteHeX v3

Digital-asset banking on SourceLess. A React + Vite single-page application over
a Supabase-compatible backend, with authorisation enforced by the database
rather than by the browser.

## What is here

    src/domains/        twelve feature domains, each declaring its own routes,
                        navigation and role guards through one registry
    src/features/auth/  session and role state
    db/                 the schema: 736 migrations plus the replay tooling that
                        rebuilds an empty database from them
    docs/               architecture, deployment, platform rules, ledger design
    .claude/agents/     the agent definitions used to build and review this

## Running it

    npm ci
    cp .env.example .env.local     # fill in the two VITE_ values
    npm run dev

`VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` are inlined into the
bundle at **build** time, not read at runtime, so a built artifact is bound to
one backend and changing either means rebuilding. `src/lib/supabase.ts` throws
at startup if either is missing — deliberately, so a missing variable is a clear
error rather than a session silently reading the wrong database. See
`docs/DEPLOYMENT.md`.

    npm test          # 143 unit tests
    npm run build

## Two ideas worth knowing before reading the code

**Authorisation is the database's job.** Every guard in the UI decides what to
*offer*. What a member may actually do is decided by RLS policies and by
`SECURITY DEFINER` functions that re-check the caller. A component that forgets
a check is a cosmetic bug, not a breach.

**The ledger refuses to be wrong.** `post_entries` rejects any batch whose
signed amounts do not sum to zero per asset, so a credit with no matching debit
is not something to catch in review — it is a transaction the database will not
accept. Balances carried over from the previous platform arrive as *claims* in
quarantine and become real only when an administrator approves them, which posts
them through that same function against `opening_equity`.

## Licence

MIT — see [LICENSE](LICENSE).
