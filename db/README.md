# `db/` — the migration history, and the CI gate that replays it

This directory is **not part of the application**. Nothing under `src/` imports
it, `tsc` does not compile it, ESLint ignores it and `.dockerignore` keeps it
out of the image. It exists for one job: proving in CI that the schema v3 reads
still builds from an empty database.

    npm run db:replay
    npm run db:replay -- --json replay-report.json

## Why it is vendored here

The migration history and the tooling that replays it live in
`c:/tmp/ignitehex-v2`. That tree has no CI and no remote, so a CI job cannot
reach it. Copying it in is the honest trade: v3's CI can only gate on what is in
v3's checkout.

The consequence is that **this is a copy and will drift.** Re-sync it when v2's
migrations change:

    cp c:/tmp/ignitehex-v2/supabase/migrations/*.sql        db/supabase/migrations/
    cp c:/tmp/ignitehex-v2/scripts/repair-migrations.mjs    db/scripts/
    cp c:/tmp/ignitehex-v2/scripts/gen-recovered-schema.mjs db/scripts/
    cp c:/tmp/ignitehex-v2/scripts/schema-facts.json        db/scripts/
    cp c:/tmp/ignitehex-v2/src/integrations/supabase/types.ts db/src/integrations/supabase/

`hostless-db.mjs` is the one file that is **not** a straight copy — see below.
The layout under `db/` mirrors v2's repository root because the vendored scripts
resolve `scripts/…`, `supabase/migrations` and
`src/integrations/supabase/types.ts` relative to the working directory.
`scripts/run-replay.mjs` sets that working directory to `db/`, so no path inside
the vendored scripts had to be rewritten and re-syncing stays a plain `cp`.

## What the job actually does

PGlite is real PostgreSQL compiled to WebAssembly, running inside Node. No
Docker, no service container, no daemon, no credentials — which is why this can
run on every push. Every migration is applied in order to an empty database and
the result is classified three ways:

| bucket | meaning | gates? |
|---|---|---|
| `applied` | the file applied, possibly after a retry | no |
| `data-only` | the file backfills rows that only ever existed in the live database and cannot exist in an empty one | **no** |
| `FAILED` | the file did not apply and the reason is not a data backfill | **yes** |

`db/replay-baseline.json` holds the accepted `FAILED` count. The job fails when
the count **rises above** it. Raising that number is a deliberate act and
belongs in the same commit as whatever caused the rise, with the reason written
into the file's `notes`. Lowering it is free.

The counts are checked to add up (`applied + data-only + FAILED == migrations`)
and the run aborts with exit 2 if they do not. An earlier version of this
driver dropped six files out of all three counts and nothing noticed.

## What was changed from v2's copy, and why

Run unmodified against the current history, v2's `hostless-db.mjs` **crashes and
prints no report at all**: it dies on an unhandled `25P02 current transaction is
aborted` from the catalogue query at the end. Four changes:

1. **Reset after a failure.** PGlite holds one session for the whole run, so the
   first migration to fail inside a transaction block poisons every migration
   after it and the summary queries too. A `ROLLBACK` in the catch clears it.
   This is what turns a crash into a report.

2. **The same two retries the Docker driver uses**, ported from
   `rebuild-local.mjs`: `DROP FUNCTION … CASCADE` in front of a file that
   changes a function's signature, and a replay with
   `session_replication_role = replica` for a data backfill. Without them the
   two drivers disagree by dozens of files and neither number means anything.

3. **`CREATE EXTENSION` for pgcrypto / pg_cron / pg_net / uuid-ossp is
   neutralised in the staged copy.** The prelude already supplies the surface
   the migrations call — `crypt()`, `gen_salt()`, `digest()`, `cron.schedule()`,
   `net.http_post()` — and PGlite's base build has none of these extensions, so
   the statement itself was the only thing failing. The prelude also gained
   `storage.foldername()`, `realtime.messages`, the `supabase_realtime`
   publication and a fuller `auth.users`, all for the same reason.

4. **Only timestamped files are replayed.** `PENDING_PRODUCTION_*.sql` is a
   staged production change awaiting review, not a migration, and has no
   position in the history. Its own header claims `rebuild-local.mjs` skips it;
   neither driver did. This one does, and prints what it skipped.

Together these moved the run from *crash, no output* to **732 migrations,
725 applied, 6 data-only, 1 FAILED**.

## What this build is NOT

Not a stack you can point an application at. There is no PostgREST, no GoTrue
and no realtime, and the crypto functions in the prelude are **not
cryptography** — `crypt()` is a bare SHA-256 so that DDL referencing the name
can be created. For a stack that serves the app, use
`c:/tmp/ignitehex-selfhost` (`docker compose up`).

Not a check that the schema is *correct*, either. It proves the history still
builds. Whether what it builds matches production is a different question, and
`docs/FINDINGS.md` F-004 / F-009 / F-010 / F-011 / F-020 are what came of asking
it.
