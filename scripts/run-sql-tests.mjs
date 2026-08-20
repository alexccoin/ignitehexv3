#!/usr/bin/env node
/**
 * Database and authorisation tests, run against the self-hosted stack.
 *
 * Derived from `hex-ignite-nexus/scripts/run-sql-tests.mjs`, which runs each
 * test as a psql script inside the container. That convention is kept for the
 * ledger invariants — a transaction that ends in ROLLBACK is the cleanest way
 * to assert a constraint — but it is NOT sufficient on its own, and this
 * harness exists because of the difference:
 *
 *   psql runs as `postgres`. `postgres` is the owner, bypasses RLS, and is the
 *   identity every SECURITY DEFINER function already trusts. An authorisation
 *   test executed there proves nothing whatsoever about a browser caller. It is
 *   the single easiest way to write a green test suite over an open database.
 *
 * So authorisation is tested the way a member actually reaches the platform:
 * sign in over `/auth/v1/token`, get a real member JWT, and call PostgREST on
 * :55321 with it. What comes back is what the browser would get.
 *
 * Two kinds of test file are collected from tests/sql/:
 *
 *   *.sql   a self-contained transaction ending in ROLLBACK, run through psql
 *           in the container. For invariants of the database itself.
 *   *.mjs   a module default-exporting { name, cases: [{ name, run(ctx) }] }.
 *           `ctx` carries `sql()` for setup and verification, and `api()` /
 *           `as.member` / `as.admin` for calls made as a real signed-in user.
 *
 * A case fails by throwing. `expect` below throws with the observed value in
 * the message, because a failure that does not print what it saw costs another
 * round trip to diagnose.
 *
 * Usage:
 *   node scripts/run-sql-tests.mjs
 *   node scripts/run-sql-tests.mjs --container ignitehex-db-1 --api http://localhost:55321
 *   node scripts/run-sql-tests.mjs --only authorization
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIR = join(ROOT, 'tests', 'sql');

const CONTAINER = flag('container', 'ignitehex-db-1');
const API = (flag('api', 'http://localhost:55321') || '').replace(/\/$/, '');
const ENV_FILE = flag('env', 'c:/tmp/ignitehex-selfhost/.env');
const ONLY = flag('only', null);
const PASSWORD = flag('password', 'LocalDev123!');

/* ------------------------------------------------------------------ env */

/** Read KEY=VALUE from the stack's .env. Nothing here is committed. */
function readEnv(path) {
  if (!existsSync(path)) {
    throw new Error(
      `No env file at ${path}. Pass --env <path> pointing at the self-hosted stack's .env.`
    );
  }
  const out = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
  return out;
}

const env = readEnv(ENV_FILE);
for (const key of ['POSTGRES_PASSWORD', 'ANON_KEY']) {
  if (!env[key]) throw new Error(`${key} missing from ${ENV_FILE}`);
}

/* ------------------------------------------------------------------ sql */

/**
 * Run SQL in the container as `postgres`.
 *
 * This is the privileged path: use it for fixtures, for reading back what a
 * write actually did, and for the ledger invariants. Never use it to test
 * whether someone is allowed to do something.
 */
function sql(text, { rows = false } = {}) {
  const out = execFileSync(
    'docker',
    [
      'exec',
      '-i',
      '-e',
      `PGPASSWORD=${env.POSTGRES_PASSWORD}`,
      CONTAINER,
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-q',
      '-v',
      'ON_ERROR_STOP=1',
      ...(rows ? ['-At', '-F', '\u0001'] : []),
      '-f',
      '-',
    ],
    { input: text, stdio: ['pipe', 'pipe', 'pipe'], timeout: 60_000 }
  ).toString();
  if (!rows) return out;
  return out
    .split('\n')
    .filter((l) => l.length)
    .map((l) => l.split('\u0001'));
}

/**
 * Run a whole .sql file and return stdout AND stderr together.
 *
 * psql writes RAISE NOTICE to stderr, and a test file's NOTICEs are its running
 * commentary — dropping them turns a passing test into a bare "PASS" that says
 * nothing about what it actually proved.
 */
function psqlFile(text) {
  const res = spawnSync(
    'docker',
    [
      'exec', '-i',
      '-e', `PGPASSWORD=${env.POSTGRES_PASSWORD}`,
      CONTAINER,
      'psql', '-U', 'postgres', '-d', 'postgres',
      '-q', '-v', 'ON_ERROR_STOP=1', '-f', '-',
    ],
    { input: text, encoding: 'utf8', timeout: 120_000 }
  );
  return {
    ok: res.status === 0,
    out: `${res.stdout || ''}${res.stderr || ''}`.trim(),
  };
}

/** The single scalar a query returns. */
const scalar = (text) => {
  const rows = sql(text, { rows: true });
  return rows.length ? rows[0][0] : null;
};

/* ------------------------------------------------------------------ api */

async function signIn(email) {
  const res = await fetch(`${API}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  const body = await res.json();
  if (!res.ok || !body.access_token) {
    throw new Error(`sign-in failed for ${email}: HTTP ${res.status} ${JSON.stringify(body)}`);
  }
  return { token: body.access_token, userId: body.user.id, email };
}

/**
 * One PostgREST call, made as a specific signed-in user.
 *
 * `apikey` is always the anon key — that is what the browser ships. The bearer
 * token is what carries the identity, and it is the only thing that changes
 * between a member call and an admin call.
 */
async function api(path, { method = 'GET', body, as, prefer } = {}) {
  const headers = {
    apikey: env.ANON_KEY,
    'Content-Type': 'application/json',
    ...(as ? { Authorization: `Bearer ${as.token}` } : {}),
    ...(prefer ? { Prefer: prefer } : {}),
  };
  const res = await fetch(`${API}${path}`, {
    method,
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await res.text();
  let parsed = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text;
  }
  return { status: res.status, body: parsed, raw: text };
}

/** POST an RPC as a given user. */
const rpc = (name, params, opts) =>
  api(`/rest/v1/rpc/${name}`, { method: 'POST', body: params, ...opts });

/* --------------------------------------------------------- assertions */

class Failed extends Error {}

const show = (v) => (typeof v === 'string' ? v : JSON.stringify(v));

const expect = {
  equal(actual, wanted, what) {
    if (actual !== wanted) {
      throw new Failed(`${what}\n            wanted ${show(wanted)}\n            got    ${show(actual)}`);
    }
  },
  ok(cond, what, detail) {
    if (!cond) throw new Failed(`${what}${detail === undefined ? '' : `\n            got    ${show(detail)}`}`);
  },
  /** A call the platform must refuse. Accepts the HTTP codes PostgREST uses
   *  for a refusal, and reports the body when it does not refuse. */
  denied(res, what) {
    const refused =
      res.status === 401 ||
      res.status === 403 ||
      res.status === 404 ||
      (res.status === 200 && Array.isArray(res.body) && res.body.length === 0) ||
      res.status === 204;
    if (!refused) {
      throw new Failed(`${what}\n            got    HTTP ${res.status} ${show(res.body)}`);
    }
  },
  /** A call that must be refused by a permission error specifically, not by a
   *  missing row, a bad argument or a typo in the function name. */
  permissionDenied(res, what) {
    const code = res.body && typeof res.body === 'object' ? res.body.code : null;
    if (res.status !== 403 || code !== '42501') {
      throw new Failed(
        `${what}\n            wanted HTTP 403 / SQLSTATE 42501` +
          `\n            got    HTTP ${res.status} ${show(res.body)}`
      );
    }
  },
  async throwsSql(fn, sqlstateOrText, what) {
    let raised = null;
    try {
      await fn();
    } catch (err) {
      raised = (err.stderr?.toString() || err.message || '').trim();
    }
    if (raised === null) throw new Failed(`${what}\n            got    no error at all`);
    if (!raised.includes(sqlstateOrText)) {
      throw new Failed(
        `${what}\n            wanted an error mentioning ${show(sqlstateOrText)}` +
          `\n            got    ${raised.split('\n').slice(0, 3).join(' / ')}`
      );
    }
    return raised;
  },
};

/* ------------------------------------------------------------------ run */

console.log('\n  Database and authorisation tests');
console.log(`  container ${CONTAINER} · api ${API}`);
console.log('  ' + '─'.repeat(70) + '\n');

const files = existsSync(DIR) ? readdirSync(DIR).sort() : [];
if (!files.length) {
  console.log(`  No tests found in ${DIR}\n`);
  process.exit(1);
}

let passed = 0;
let failed = 0;
const failures = [];

/** Shared context handed to every .mjs test module. */
const ctx = {
  sql,
  scalar,
  api,
  rpc,
  expect,
  Failed,
  as: {},
  env: { API, CONTAINER, ANON_KEY: env.ANON_KEY },
};

// One sign-in per role, reused by every case. Doing it per case would make the
// suite mostly a load test of GoTrue.
try {
  ctx.as.member = await signIn('newbie@ignitehex.local');
  ctx.as.admin = await signIn('admin@ignitehex.local');
  ctx.as.other = await signIn('investor1@ignitehex.local');
  console.log(`  signed in: member ${ctx.as.member.userId}`);
  console.log(`             admin  ${ctx.as.admin.userId}`);
  console.log(`             other  ${ctx.as.other.userId}\n`);
} catch (err) {
  console.error(`  Could not sign in against ${API}: ${err.message}`);
  console.error('  Is the self-hosted stack up, and has it been seeded?\n');
  process.exit(1);
}

function record(name, err) {
  if (!err) {
    passed++;
    console.log(`    PASS  ${name}`);
    return;
  }
  failed++;
  failures.push({ name, err });
  console.log(`    FAIL  ${name}`);
  const message = err instanceof Failed ? err.message : `${err.name}: ${err.message}`;
  for (const line of message.split('\n')) console.log(`          ${line}`);
}

for (const file of files) {
  if (ONLY && !file.includes(ONLY)) continue;

  /* --- a psql script, ROLLBACK convention ------------------------------ */
  if (file.endsWith('.sql')) {
    console.log(`  ${file}`);
    const result = psqlFile(readFileSync(join(DIR, file), 'utf8'));
    const err = result.ok
      ? null
      : new Failed(
          result.out
            .split('\n')
            .filter((l) => l.trim() && !l.includes('NOTICE:'))
            .slice(0, 8)
            .map((l) => l.replace(/^psql:<stdin>:\d+:\s*/, ''))
            .join('\n')
        );
    record(file, err);
    for (const line of result.out.split('\n').filter((l) => l.includes('NOTICE:'))) {
      console.log(`          ${line.replace(/^.*NOTICE:\s*/, '')}`);
    }
    console.log('');
    continue;
  }

  /* --- a module of cases ----------------------------------------------- */
  if (!file.endsWith('.mjs')) continue;

  const mod = (await import(pathToFileURL(join(DIR, file)).href)).default;
  console.log(`  ${file} — ${mod.name}`);

  if (mod.setup) {
    try {
      await mod.setup(ctx);
    } catch (e) {
      record(`${file} setup`, e);
      console.log('');
      continue;
    }
  }

  for (const testCase of mod.cases) {
    let err = null;
    try {
      await testCase.run(ctx);
    } catch (e) {
      err = e;
    }
    record(testCase.name, err);
  }

  if (mod.teardown) {
    try {
      await mod.teardown(ctx);
    } catch (e) {
      record(`${file} teardown`, e);
    }
  }
  console.log('');
}

console.log('  ' + '─'.repeat(70));
console.log(`  ${passed} passed · ${failed} failed\n`);

if (failed) {
  console.log('  Failed:');
  for (const f of failures) console.log(`    ${f.name}`);
  console.log('');
}

process.exit(failed > 0 ? 1 : 0);
