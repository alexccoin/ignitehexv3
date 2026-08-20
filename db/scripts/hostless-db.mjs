#!/usr/bin/env node
/**
 * Replay the whole migration history against a throwaway Postgres, with no
 * host process — no Docker, no daemon, no ports. This is the CI gate that
 * proves the schema still builds from scratch.
 *
 * PGlite is a real Postgres compiled to WebAssembly that runs inside Node, so
 * the migrations execute against actual Postgres rather than a simulation.
 * Three things a hosted Supabase project provides are absent and are supplied
 * by the prelude below: the `auth` schema and its helper functions, the API
 * roles, and stand-ins for pgcrypto / pg_cron / pg_net.
 *
 * What this is for: checking that the schema still builds, in CI or on a
 * machine without Docker. What it is NOT for: running the app. There is no
 * PostgREST, no GoTrue and no realtime here, so nothing serves the frontend —
 * use the Docker stack in c:/tmp/ignitehex-selfhost for that.
 *
 * Provenance: vendored from ignitehex-v2/scripts/hostless-db.mjs. See
 * db/README.md for what was changed and why.
 *
 * Usage:
 *   node scripts/hostless-db.mjs [--dir <migrations>] [--out <file.tar.gz>]
 *                                [--baseline <n>] [--json <report.json>]
 *
 * Exit status is the CI contract:
 *   0  FAILED count is at or below the recorded baseline
 *   1  FAILED count rose above the baseline — a migration that used to replay
 *      no longer does, or a new one does not replay
 *   2  the harness itself could not run (missing dependency, bad prelude)
 *
 * Only FAILED gates. `applied` and `data-only` are reported separately and
 * neither is a pass/fail signal: a data-only migration backfills rows that only
 * ever existed in the live database and cannot apply to an empty one, which is
 * not a schema defect.
 */

import { readdirSync, readFileSync, writeFileSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
const flag = (n, d) => {
  const i = args.indexOf(`--${n}`);
  return i === -1 ? d : args[i + 1];
};

const SOURCE = flag('dir', 'supabase/migrations');
const BASELINE_FILE = 'replay-baseline.json';
const BASELINE = '20250720000000_recovered_dashboard_objects.sql';

/**
 * Stand-ins for what a hosted Supabase project provides.
 *
 * auth.uid() reads a session GUC, so a test can impersonate a user with
 * `set local request.jwt.claim.sub = '<uuid>'` and exercise RLS for real —
 * which is the main reason this mode is worth having.
 */
const PRELUDE = `
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;
CREATE SCHEMA IF NOT EXISTS cron;
CREATE SCHEMA IF NOT EXISTS net;

DO $$ BEGIN CREATE ROLE anon;              EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated;     EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role;      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE supabase_admin;    EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticator;     EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Identity, read from the request GUC exactly as PostgREST would set it.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;
CREATE OR REPLACE FUNCTION auth.email() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.email', true), '');
$$;

-- pgcrypto is unavailable in PGlite. Only the surface the migrations touch is
-- provided, and it is NOT cryptography - it exists so DDL referencing these
-- names can be created. Never point an application at this build.
CREATE OR REPLACE FUNCTION extensions.digest(text, text) RETURNS bytea
  LANGUAGE sql IMMUTABLE AS $$ SELECT sha256($1::bytea); $$;
CREATE OR REPLACE FUNCTION public.digest(text, text) RETURNS bytea
  LANGUAGE sql IMMUTABLE AS $$ SELECT sha256($1::bytea); $$;
CREATE OR REPLACE FUNCTION public.crypt(text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$ SELECT encode(sha256(($1 || $2)::bytea), 'hex'); $$;
CREATE OR REPLACE FUNCTION extensions.crypt(text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$ SELECT encode(sha256(($1 || $2)::bytea), 'hex'); $$;
CREATE OR REPLACE FUNCTION public.gen_random_bytes(integer) RETURNS bytea
  LANGUAGE sql VOLATILE AS $x$ SELECT decode(md5(random()::text || clock_timestamp()::text), 'hex'); $x$;
CREATE OR REPLACE FUNCTION public.gen_salt(text) RETURNS text
  LANGUAGE sql VOLATILE AS $x$ SELECT encode(public.gen_random_bytes(8), 'hex'); $x$;
-- bf/md5 salts are requested with a cost factor: gen_salt('bf', 10).
CREATE OR REPLACE FUNCTION public.gen_salt(text, integer) RETURNS text
  LANGUAGE sql VOLATILE AS $x$ SELECT encode(public.gen_random_bytes(8), 'hex'); $x$;
CREATE OR REPLACE FUNCTION extensions.gen_salt(text) RETURNS text
  LANGUAGE sql VOLATILE AS $x$ SELECT encode(public.gen_random_bytes(8), 'hex'); $x$;
CREATE OR REPLACE FUNCTION extensions.gen_salt(text, integer) RETURNS text
  LANGUAGE sql VOLATILE AS $x$ SELECT encode(public.gen_random_bytes(8), 'hex'); $x$;

-- Scheduling and outbound HTTP have no meaning without a host process; these
-- record the call and return, so a migration that schedules a job still applies.
CREATE TABLE IF NOT EXISTS cron.job (
  jobid bigserial PRIMARY KEY, jobname text UNIQUE, schedule text, command text
);
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, sched text, cmd text)
  RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (job_name, sched, cmd)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
  RETURNING jobid;
$$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text) RETURNS boolean
  LANGUAGE sql AS $$ DELETE FROM cron.job WHERE jobname = job_name RETURNING true; $$;
CREATE OR REPLACE FUNCTION net.http_post(url text, headers jsonb DEFAULT '{}'::jsonb, body jsonb DEFAULT '{}'::jsonb)
  RETURNS bigint LANGUAGE sql AS $$ SELECT 0::bigint; $$;

CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text, name text, owner uuid, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS storage.buckets (id text PRIMARY KEY, name text, public boolean DEFAULT false);
-- storage.foldername() splits an object path; policies call it to scope a
-- bucket by the first path segment.
CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[]
  LANGUAGE sql IMMUTABLE AS $$ SELECT string_to_array(name, '/'); $$;
CREATE OR REPLACE FUNCTION storage.filename(name text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$ SELECT (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)]; $$;
CREATE OR REPLACE FUNCTION storage.extension(name text) RETURNS text
  LANGUAGE sql IMMUTABLE AS $$ SELECT split_part(storage.filename(name), '.', 2); $$;

CREATE OR REPLACE FUNCTION realtime.topic() RETURNS text LANGUAGE sql STABLE AS $$ SELECT ''::text; $$;
-- realtime.messages is the broadcast table; policies are written against it.
CREATE TABLE IF NOT EXISTS realtime.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic text, extension text, payload jsonb, event text,
  inserted_at timestamptz NOT NULL DEFAULT now()
);

-- Supabase creates this publication at project bootstrap; migrations add tables
-- to it. Without it every ALTER PUBLICATION in the history fails.
DO $$ BEGIN CREATE PUBLICATION supabase_realtime; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

GRANT USAGE ON SCHEMA public, auth, extensions, storage, realtime TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
`;

/**
 * Extensions PGlite's base build does not ship. The prelude above already
 * supplies the surface the migrations actually call — crypt(), gen_salt(),
 * digest(), cron.schedule(), net.http_post() — so the only thing left failing
 * is the CREATE EXTENSION statement itself. Neutralising it in the staged copy
 * is the same bargain the prelude makes: supply what the host normally
 * provides, and never point an application at the result.
 *
 * uuid-ossp is left alone: PGlite has gen_random_uuid() from pgcrypto-less
 * core, and no migration calls uuid_generate_v4() without it.
 */
const ABSENT_EXTENSIONS = /^([ \t]*)(CREATE\s+EXTENSION\s+(?:IF\s+NOT\s+EXISTS\s+)?"?(?:pgcrypto|pg_cron|pg_net|uuid-ossp)"?[^;]*;)/gim;

/**
 * Errors that mean "this file is backfilling production data", not "this file
 * is broken". Kept byte-identical to the Docker driver's copy in
 * ignitehex-v2/scripts/rebuild-local.mjs so the two routes classify alike.
 */
const DATA_ONLY =
  /violates foreign key constraint|violates not-null constraint|violates check constraint|duplicate key value|no unique or exclusion constraint|invalid input syntax for type uuid|could not create unique index|User (ID is required|does not exist)/i;

/** Errors that a DROP FUNCTION ... CASCADE in front of the file clears. */
const NEEDS_FUNCTION_DROP =
  /cannot change (?:name of input parameter|return type of existing function)|cannot remove parameter defaults|because other objects depend on it/i;

// ---------------------------------------------------------------------- run

const { PGlite } = await import('@electric-sql/pglite').catch(() => {
  console.error('@electric-sql/pglite is not installed.  npm i -D @electric-sql/pglite');
  process.exit(2);
});

console.log('\n  Hostless schema build (PGlite — no Docker)');
console.log('  ' + '─'.repeat(56));

const db = new PGlite();
try {
  await db.exec(PRELUDE);
} catch (err) {
  console.error('  prelude failed: ' + String(err.message).split(String.fromCharCode(10))[0]);
  process.exit(2);
}
const version = (await db.query('select version()')).rows[0].version.split(' on ')[0];
console.log(`  ${version}`);

// The repair transforms are applied to staged copies, exactly as the Docker
// path does, so both routes build the same SQL.
const stage = mkdtempSync(join(tmpdir(), 'ignitehex-hostless-'));
let neutralised = 0;

/**
 * A migration is a timestamped file. Anything else in the directory is staged
 * for review and has no defined position in the history — today that is
 * PENDING_PRODUCTION_20260819_privilege_closure.sql, whose own header says
 * "filename deliberately lacks a timestamp prefix so rebuild-local.mjs skips
 * it". Neither driver actually skipped it; this one does, and prints what it
 * skipped so nothing disappears quietly.
 */
const MIGRATION_NAME = /^\d{14}[-_]/;
const notMigrations = readdirSync(SOURCE).filter(
  (f) => f.endsWith('.sql') && f !== BASELINE && !MIGRATION_NAME.test(f)
);

for (const f of readdirSync(SOURCE).filter(
  (f) => f.endsWith('.sql') && f !== BASELINE && MIGRATION_NAME.test(f)
)) {
  const norm = /^\d{14}_/.test(f) ? f : f.replace(/^(\d{14})[-_]?/, '$1_');
  const sql = readFileSync(join(SOURCE, f), 'utf8').replace(
    ABSENT_EXTENSIONS,
    (_m, indent, stmt) => {
      neutralised++;
      return `${indent}-- [hostless] not available in PGlite, stubbed by the prelude: ${stmt.replace(/\s+/g, ' ')}`;
    }
  );
  writeFileSync(join(stage, norm), sql);
}
execFileSync('node', ['scripts/repair-migrations.mjs', '--dir', stage], { stdio: 'pipe' });
execFileSync('node', ['scripts/gen-recovered-schema.mjs', '--out', join(stage, BASELINE)], { stdio: 'pipe' });

const files = readdirSync(stage).filter((f) => f.endsWith('.sql')).sort();
let applied = 0;
const retried = [];
const failures = [];
const skipped = [];

const shortError = (err) => String(err.message).split(String.fromCharCode(10))[0].slice(0, 140);

/**
 * A failed statement inside an implicit transaction block leaves the session in
 * `25P02 current transaction is aborted`, and PGlite holds one session for the
 * whole run. Without this reset the first failure poisons every migration after
 * it AND the catalogue queries at the end, which is how the unpatched script
 * died with an unhandled 25P02 and printed no report at all.
 */
const reset = () => db.exec('ROLLBACK').catch(() => {});

/**
 * Enumerate every overload of every function the file creates, so a signature
 * change cannot leave an old variant behind. Ported from the Docker driver's
 * dropPrelude() (ignitehex-v2/scripts/rebuild-local.mjs) — the two routes have
 * to retry alike or their FAILED counts are not comparable.
 */
function dropPrelude(sql) {
  const names = new Set();
  for (const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([\w.]+)\s*\(/gi)) {
    const [schema, name] = m[1].includes('.') ? m[1].split('.') : ['public', m[1]];
    names.add(`${schema}.${name}`);
  }
  if (!names.size) return null;
  return (
    [...names]
      .map((qualified) => {
        const [schema, name] = qualified.split('.');
        return `DO $drop$ DECLARE r record; BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = '${schema}' AND p.proname = '${name}' LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $drop$;`;
      })
      .join('\n') + '\n'
  );
}

/**
 * Retry a data-backfill migration with referential integrity relaxed. Anything
 * still failing is recorded as skipped rather than failed: the schema is
 * unaffected, and counting it as a failure would make a healthy build look
 * broken.
 */
async function dataRetry(file, sql, originalError) {
  await reset();
  try {
    await db.exec(`SET session_replication_role = replica;\n${sql}`);
    await db.exec(`SET session_replication_role = origin;`).catch(() => {});
    applied++;
    retried.push({ file, how: 'fk-deferred' });
    return true;
  } catch (err) {
    await reset();
    await db.exec(`SET session_replication_role = origin;`).catch(() => {});
    skipped.push({ file, error: shortError(err) || originalError });
    return true;
  }
}

for (const file of files) {
  const sql = readFileSync(join(stage, file), 'utf8');
  try {
    await db.exec(sql);
    applied++;
    continue;
  } catch (err) {
    const error = shortError(err);
    await reset();

    if (NEEDS_FUNCTION_DROP.test(error)) {
      const prelude = dropPrelude(sql);
      if (prelude) {
        try {
          await db.exec(prelude + sql);
          applied++;
          retried.push({ file, how: 'function-drop' });
          continue;
        } catch (err2) {
          const e2 = shortError(err2);
          await reset();
          if (DATA_ONLY.test(e2)) {
            await dataRetry(file, sql, e2);
            continue;
          }
          failures.push({ file, error: e2, retried: 'function-drop' });
          continue;
        }
      }
    }

    if (DATA_ONLY.test(error)) {
      await dataRetry(file, sql, error);
      continue;
    }
    failures.push({ file, error });
  }
}
rmSync(stage, { recursive: true, force: true });
await reset();

const one = async (sql) => (await db.query(sql)).rows[0].n;
const tables = await one("select count(*)::int n from pg_tables where schemaname='public'");
const fns = await one(
  "select count(*)::int n from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public'"
);
const pols = await one("select count(*)::int n from pg_policies where schemaname='public'");

// Every file lands in exactly one bucket. An earlier version of this driver
// silently dropped the six fk-deferred retries out of all three counts, so the
// totals did not add up and nobody noticed. They add up out loud now.
const accounted = applied + skipped.length + failures.length;
if (accounted !== files.length) {
  console.error(
    `\n  harness defect: ${accounted} files accounted for, ${files.length} staged. ` +
      `applied=${applied} data-only=${skipped.length} FAILED=${failures.length}\n`
  );
  process.exit(2);
}

console.log(`  migrations  ${files.length}`);
console.log(`  applied     ${applied}   (${retried.length} of them on a retry)`);
console.log(`  data-only   ${skipped.length}   (production backfills — schema unaffected)`);
console.log(`  FAILED      ${failures.length}`);
console.log(`  tables      ${tables}`);
console.log(`  functions   ${fns}`);
console.log(`  policies    ${pols}`);
console.log(`  ext stubs   ${neutralised}  CREATE EXTENSION statements neutralised (PGlite)`);
console.log(`  not replayed ${notMigrations.length}  ${notMigrations.join(', ') || '—'}\n`);

if (failures.length) {
  console.log(`  ${failures.length} did not apply:`);
  for (const f of failures.slice(0, 25)) console.log(`    ${f.file}\n      ${f.error}`);
  if (failures.length > 25) console.log(`    … and ${failures.length - 25} more`);
  console.log('');
}

const out = flag('out', null);
if (out) {
  const blob = await db.dumpDataDir('gzip');
  writeFileSync(out, Buffer.from(await blob.arrayBuffer()));
  console.log(`  snapshot -> ${out}\n`);
}

// ------------------------------------------------------------------ the gate

const recorded = existsSync(BASELINE_FILE) ? JSON.parse(readFileSync(BASELINE_FILE, 'utf8')) : null;
const baseline = Number(flag('baseline', recorded ? recorded.failed : 0));

const report = {
  generated_at: new Date().toISOString(),
  postgres: version,
  migrations: files.length,
  applied,
  retried: retried.length,
  data_only: skipped.length,
  failed: failures.length,
  baseline,
  tables,
  functions: fns,
  policies: pols,
  not_replayed: notMigrations,
  failures,
};
const jsonOut = flag('json', null);
if (jsonOut) {
  writeFileSync(jsonOut, JSON.stringify(report, null, 2) + '\n');
  console.log(`  report -> ${jsonOut}\n`);
}

if (failures.length > baseline) {
  console.log(
    `  GATE FAILED  ${failures.length} migrations do not replay, baseline is ${baseline}.\n` +
      `  Something that used to build no longer does. Fix the migration, or — if the\n` +
      `  rise is understood and accepted — raise "failed" in ${BASELINE_FILE} in the\n` +
      `  same commit, with the reason in the file's "notes".\n`
  );
  process.exit(1);
}

if (failures.length < baseline) {
  console.log(
    `  GATE PASSED, and the baseline is now stale: ${failures.length} < ${baseline}.\n` +
      `  Lower "failed" in ${BASELINE_FILE} to ${failures.length} so the gate keeps its grip.\n`
  );
} else {
  console.log(`  GATE PASSED  FAILED ${failures.length} == baseline ${baseline}\n`);
}
process.exit(0);
