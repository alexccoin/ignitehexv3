# Deploying IgniteHeX v3

**Written 2026-08-19.** v3 is a static React/Vite SPA. It has no server of its
own: everything it does is a request from the browser to a Supabase-compatible
backend, authorised by that backend's RLS. Deploying it means publishing a
directory of files and pointing them at a backend.

Read §6 before deploying anywhere a member can reach it. The application builds,
typechecks, tests and serves clean; several things underneath it do not, and
some of them move money.

---

## 1. The one thing that surprises everybody

**`VITE_*` variables are baked into the JavaScript at build time. They are not
read at runtime.**

```
$ grep -c 'ci.invalid' dist/assets/index-DlYFPlGt.js
1
```

That was a build run with `VITE_SUPABASE_URL=http://ci.invalid`. The string is
*in the bundle*. Consequences, all of which have bitten someone:

- `docker run -e VITE_SUPABASE_URL=…` does nothing. The bundle is already
  written. It must be `docker build --build-arg`.
- A built artifact is bound to one backend. Promoting the same `dist/` from
  staging to production **does not repoint it** — you must rebuild.
- Changing a variable on the host requires a *rebuild*, not a restart.

`src/lib/supabase.ts` throws at startup if either variable is missing, on
purpose, so a missing variable is a blank page with a clear console error rather
than a session silently reading the wrong database. There is no fallback and
none should be added.

## 2. The two backends

The app reads exactly two variables. Nothing else in the frontend selects a
backend.

| | `VITE_SUPABASE_URL` | `VITE_SUPABASE_PUBLISHABLE_KEY` |
|---|---|---|
| **Self-hosted** (`c:/tmp/ignitehex-selfhost`, `docker compose up`) | `http://localhost:${KONG_HTTP_PORT}` — 55321 | the `ANON_KEY` value from that stack's `.env` |
| **Hosted project** | `https://<project-ref>.supabase.co` | the anon / publishable key from the dashboard, Settings → API |

Secrets are named here, never quoted. The self-hosted stack's `.env` is
local-only and no value from it belongs in this repository — that mistake was
already made once and is recorded as F-042 in `FINDINGS.md`.

`src/lib/supabase.ts` derives `isLocal` from the URL, so a build pointed at
`localhost` can behave differently from one pointed at a hosted project. This is
a third reason a built artifact cannot be repointed.

**The publishable key is not a secret.** It is designed to be shipped to every
visitor and RLS is what protects the data behind it. The **service-role key is**,
it bypasses RLS entirely, and it must never appear in a `VITE_` variable, a
build argument, a CI secret used by these workflows, or an image layer. Nothing
in a deploy needs one.

## 3. Preflight — what must be true before you deploy

Everything here is checkable. Do not skip on the grounds that it was true last
time.

1. **CI is green on the commit being deployed.** `.github/workflows/ci.yml` runs
   typecheck, lint, tests, build, the migration replay and a Docker build that
   serves a page and asserts on what comes back.

2. **The two environment variables are set in the *build* environment** of
   whatever is building — not the runtime environment. See §1.

3. **The migrations are applied to the target backend**, and the schema the app
   expects is actually there. The replay job proves the history *builds*; it
   does not prove your backend *has* it. For the hosted project the migration
   history is in `c:/tmp/ignitehex-v2/supabase/migrations`.

4. **Seeds have NOT been run against production. Ever.** `seed-local.mjs`
   creates 12 users in `auth.users`, writes `user_profiles`, grants `admin` in
   `user_roles`, and sets `two_factor_enabled` on those admin accounts to
   satisfy `enforce_admin_2fa_trigger`. Against a live project that is 12 real
   accounts and a real admin grant. The seed scripts live in v2 and take
   `LOCAL_DATABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`; the guard is that you set
   those to the self-hosted stack and nothing else. There is no technical
   interlock stopping you pointing them at production — that is itself worth
   fixing.

5. **Decide, explicitly, which backend this build is for**, and tag the artifact
   with it. `ignitehex-v3:hosted` and `ignitehex-v3:selfhost` are different
   images from identical source.

## 4. Deploying

### 4a. The chosen host: Netlify

**Why Netlify and not the others.** Everything that decides what gets deployed
lives in `netlify.toml`, in the repository: the build command, the publish
directory, the SPA fallback, the cache split and the response headers. A
reviewer sees the whole deploy in the diff and there is no dashboard-only state
to drift out of sync. Vercel and Cloudflare Pages both serve this app perfectly
well; on both, the build command and output directory live in project settings
by default, which means the repository stops being the record of how the site is
built. That is the only reason. If your organisation already runs on one of the
others, the Dockerfile in §4b is the answer, not a second half-config.

Set-up, once:

```
netlify init                     # link the repo; do not accept build settings, netlify.toml has them
netlify env:set VITE_SUPABASE_URL             '<url>'   --context production
netlify env:set VITE_SUPABASE_PUBLISHABLE_KEY '<key>'   --context production
```

Set them per-context. A deploy preview that inherits production's backend gives
every pull request write access to real member data.

The SPA fallback is the part that is easy to get wrong and quiet when it is:

```toml
[[redirects]]
  from   = "/*"
  to     = "/index.html"
  status = 200
```

`status = 200` is a rewrite, not a redirect, so the URL the user typed survives
for the router to read. Without this rule every one of v3's ~50 client routes
404s on a cold load or a refresh — `/` works, so it looks fine until someone
bookmarks `/admin/exposure`.

### 4b. The host-independent option: Docker

Serves the identical bundle behind nginx with the identical fallback, for
anywhere that takes a container.

```
docker build \
  --build-arg VITE_SUPABASE_URL=https://<project>.supabase.co \
  --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key> \
  -t ignitehex-v3:hosted .

docker run --rm -p 8080:8080 ignitehex-v3:hosted
```

Multi-stage: `node:22-alpine` builds, `nginx:1.27-alpine` serves. It listens on
**8080** and runs as **uid 101 (nginx)**, not root, so it is accepted by Cloud
Run, Fly, ECS and Kubernetes policies that refuse root or privileged ports.
`/healthz` is answered by nginx itself — it says the server is up, never that
the app works. The build fails if either build-arg is missing, rather than
producing an image that throws in the user's browser.

Verified by running it, not by reading it:

```
$ docker run -d --name ihx -p 18099:8080 ignitehex-v3:ci
$ docker exec ihx id
uid=101(nginx) gid=101(nginx) groups=101(nginx)

  /                          200  shell      text/html
  /wallet                    200  shell      text/html
  /staking/withdrawals       200  shell      text/html
  /admin/exposure            200  shell      text/html
  /guardian/reserves         200  shell      text/html
  /dome/portfolio            200  shell      text/html
  /nope                      200  shell      text/html

  200  /assets/index-DlYFPlGt.js   cache=public, max-age=31536000, immutable
  404  /assets/nope.js
```

"shell" means the response body was byte-identical to `/` — the fallback is a
rewrite and serves the real shell, and a missing asset still 404s instead of
being masked by it.

### Caching

Both hosts do the same thing: `/assets/*` is fingerprinted by Vite and pinned
`immutable` for a year; `index.html` is `max-age=0, must-revalidate`. Pinning
the shell is the classic way to break a deploy — a cached `index.html` points at
asset hashes that no longer exist and the app fails to boot with nothing useful
in the console.

## 5. Rollback

The app is a directory of files and a backend. Those roll back very differently.

**The frontend rolls back cleanly.**

- *Netlify*: "Publish deploy" on the previous deploy in the dashboard, or
  `netlify rollback`. Instant, and the previous build's environment variables
  are baked into that build, so it comes back pointing where it did before.
- *Docker*: run the previous tag. Tag by content, never move `latest` — an image
  is bound to a backend by its build args, so `latest` meaning two different
  things is a rollback that silently repoints the app.

**The backend does not.** There is no down-migration in this history: 732
migrations, none of them reversible, and several carry data backfills. Rolling
back a schema change means writing a forward migration that undoes it. Plan the
deploy so the frontend can be rolled back *without* the schema being rolled
back — that is, ship schema changes ahead of the frontend that needs them, and
keep them additive.

**Rehearse this before you need it.** The recovery path has never been
exercised against production, and neither has the deploy path — see §6.

## 6. What is NOT production-ready

Carried forward from `docs/FINDINGS.md`. `docs/PRODUCTION_READINESS.md` assesses
the platform in more depth; this list is the subset that bears on putting v3 in
front of members, plus what this deployment work itself found.

### 6.1 Blocking — authorisation is not enforced in production

- **F-002 · the EP1 mint path is open.** *Both* `distribute_enhanced_rewards`
  overloads are executable by `anon` in production. The function inserts a stake
  with no balance check and no debit, reachable with no login. Enhanced pools
  hold 2,546,068,134 staked against 3,860,797 rewards recorded. Both
  `process_staking_request` overloads are also `anon`-executable and one has no
  authorization check at all.
- **F-001 · 269 SECURITY DEFINER functions are `anon`-executable in production**,
  including `admin_ban_user` and `admin_confirm_user_email`. Their in-body
  `is_admin()` checks do hold, so this is a missing layer rather than an open
  door — but anything shipped without an in-body guard is exposed by default.
- **F-039 · four tables the admin console reads have no admin read policy in
  production**: `arss_token_purchases`, `crypto_orders`, `user_wallets`,
  `withdrawal_requests`. RLS returns an empty set rather than an error, so
  **every figure on `/admin` in production is short by an unknown amount** and
  nothing logs. `crypto_orders` additionally lets an admin UPDATE every row
  while reading only their own.
- **F-008 · five production admin accounts have no 2FA.**
  `enforce_admin_2fa_trigger` is in the migration history and absent from
  production. Local is stricter than production here.
- **F-031 · `anon` and `authenticated` hold TRUNCATE on public tables in
  production.** RLS does not gate TRUNCATE. Not reachable through PostgREST
  today, so the exposure is theoretical — but the grant has no legitimate use.

The remedy for the first two is written, locally tested and **not applied**:
`PENDING_PRODUCTION_20260819_privilege_closure.sql`. Note that it is *not* part
of the replay (§`db/README.md`) and that it does not apply cleanly to a schema
built from the history alone, because `distribute_enhanced_rewards` does not
exist there (F-026). It is written for production, where the function does
exist.

### 6.2 Blocking — money moves on numbers that are not real

- **F-037 · `submit-bank-swap` prices real swaps from a hardcoded table.**
  `ETH 3200 · BTC 62000 · CCOS 9.35 · STR 0.0094`, with FX
  `USD 0.92 · CHF 1.05 · GBP 1.17`. It computes `to_amount` and writes
  `exchange_rate`, so this is what a member is paid. Live ETH during
  verification was **1,935.60**; the constant says **3200** — roughly 65% above
  market. `v3 banking/Transfers.tsx` mirrors the table byte-for-byte so the
  preview matches the receipt; **both change together or neither does.**
- **F-037 · `str-price` returns `0.028 + Math.random() * 0.0038`** and says so
  in its own log line. It is consumed by `convert-wstr-to-fiat` and
  `process-swap`, and `crypto-prices` derives CCOS, wSTR and ARSS from it. Every
  wSTR cashout and every token swap is priced by a random number.
- **F-037 · `forex-rates` invents rates on failure and returns
  `success: true`.** A caller cannot distinguish a live rate from a fallback.
- **F-007 · the exposure is still growing.** Production `fiat_wallets` books
  EUR 402,479,525.62 / USD 22,147,759.18 / CHF 9,887,785.67 / GBP 82,711.31 as
  withdrawable. USD has more than doubled since the 2026-07-08 audit.
- **F-040 · the ledger's opening-balance recognition double-counts.** It treats
  `balance` and `staked_amount` as disjoint buckets; in production 54,499 of
  56,836 rows have `balance = staked_amount`. Latent today (nothing has posted
  to the `staked` or `rewards` bucket) and live the moment anything does.

**Nothing that converts, swaps or cashes out should be enabled until there is a
real price source.** v3 already refuses most of this — see §6.4.

### 6.3 Blocking for a deploy specifically — this has never been deployed

Every one of these was found by doing this work and none of it has been
exercised against anything real:

- **No remote, no CI has ever run.** The workflow in `.github/workflows/ci.yml`
  is written and its steps have been run by hand from a clean checkout; GitHub
  Actions has never executed it. `git remote` is empty by instruction.
- **No environment exists.** No Netlify site, no registry, no DNS, no TLS
  certificate, no domain. §4 describes a deploy nobody has performed.
- **No rollback has been rehearsed** (§5), and the schema half of one cannot be
  performed at all without writing forward migrations.
- **No Content-Security-Policy.** A useful `connect-src` names the Supabase
  origin, which is per-environment and known only at build time. Generating the
  header from `VITE_SUPABASE_URL` at build is the right fix; a static value
  would be either wrong or decorative, so neither host config ships one. The
  other four security headers are set and asserted in CI.
- **No error reporting and no uptime check.** A white screen in a member's
  browser reaches nobody. F-021 is exactly this shape: a failed role lookup
  renders a spinner forever with nothing in the console, and "no roles" and
  "role lookup failed" are the same state.
- **The migration replay has one accepted failure** (`db/replay-baseline.json`)
  and 27 `CREATE EXTENSION` statements neutralised for PGlite. It proves the
  history builds; it does not prove your backend matches it.
- **`db/` is a vendored copy of v2's migrations and will drift.** Re-sync
  instructions are in `db/README.md`. Nothing detects drift automatically.
- **F-042 · a self-hosted secret was committed.** `.env.example` carried the
  self-hosted stack's real `POSTGRES_PASSWORD` as a literal. Removed
  2026-08-19; the value is still in this repository's git history. The repo has
  no remote and has never been pushed, and the credential is a local
  development database, so the exposure is contained — but it must be rotated
  before that stack is ever reachable from anywhere but this machine, and
  before this repository is pushed anywhere.

### 6.4 Known-good, so nobody re-checks it

- **F-025 · authorisation held on every probe that could be run** against the
  local stack from a member session.
- **v3 refuses to move money from the browser.** Forty-five member and operator
  actions are rendered visibly disabled with a named missing routine, rather
  than calling something that reports success on a write RLS silently dropped.
  That refusal is the single most valuable property v3 has and it should not be
  traded away to make the app look more capable.
- **The unit and valuation defects in the frontend are fixed and verified**:
  F-015 (cross-token sums), F-016 (EUR/CHF/GBP counted as USD), F-017 (BTC at
  two prices), F-022 (a failed balance fetch rendering as zero), F-027, F-032,
  F-034. Prices and balances now report *unknown* rather than a plausible
  number.
- **F-018 · the local stack's recovered RLS policies are more permissive than
  production for writes.** No RLS *write* test run against the local stack
  proves anything about production, in either direction. This is a caveat on
  testing, not a production defect.
