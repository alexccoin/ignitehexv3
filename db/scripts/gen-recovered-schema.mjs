#!/usr/bin/env node
/**
 * Generate the "recovered" baseline migration for schema objects that exist in
 * production but were never created by any file in supabase/migrations/.
 *
 * Those objects were made through the Lovable dashboard, so the migration
 * history references tables it never creates — which is why a clean replay dies
 * with 296 "relation does not exist" errors. The generated types file is the
 * only in-git record of their shape, so it is the source we reconstruct from.
 *
 * Postgres types are inferred from the TypeScript types plus column naming, and
 * foreign keys come from the Relationships blocks. The result is a shape match,
 * not a byte-for-byte dump: good enough to replay history and run the app
 * locally, and every later ALTER in the history still gets applied on top.
 *
 * TypeScript carries no DEFAULT, no CHECK, and no precise numeric type, so a
 * baseline built from types.ts alone rejects inserts production accepts (F-004:
 * user_profiles.account_status is NOT NULL DEFAULT 'active' in production, and
 * was NOT NULL with no default here). scripts/schema-facts.json holds those
 * facts, captured read-only from production by scripts/pull-schema-facts.mjs.
 * When a column appears there the facts win; the TypeScript inference below
 * stays as the fallback for anything the facts file does not cover, so this
 * script still runs - with a warning - if the facts file is absent.
 *
 * Usage: node scripts/gen-recovered-schema.mjs <table,list> [--out <file>]
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const TYPES_FILE = 'src/integrations/supabase/types.ts';
const OUT = flag('out', 'supabase/migrations/20250720000000_recovered_dashboard_objects.sql');

/**
 * Tables the migration history references but never creates. Derived from
 * replaying the history against a clean database and collecting every
 * "relation does not exist" failure - the list grew as earlier failures were
 * fixed and unmasked later ones.
 */
const GAP_TABLES = [
  // The last five are not referenced anywhere in the history, so they never
  // surfaced as a replay failure - they are here because the generated types
  // declare them, which means application code expects them to exist.
  'ai_usage_sessions', 'capacity_sharing', 'learning_contributions',
  'pending_balance_locks', 'str_domain_connections',
  'airdrop_registrations', 'arss_transactions', 'arx_audit_trail', 'arx_club_members',
  'arx_treasury_transactions', 'auth_attempts', 'ccoin_bank_applications', 'ccoin_banking_profiles',
  'ccoin_validations', 'crypto_wallets', 'currency_exchanges', 'domain_marketplace_bids',
  'domain_marketplace_listings', 'domain_marketplace_transactions', 'enhanced_rate_limits',
  'enhanced_staking_pools', 'fiat_transactions', 'fiat_wallets', 'github_integrations',
  'governance_proposals', 'guardian_flash_alerts', 'guardian_invitations', 'guardian_wallets',
  'iban_accounts', 'ipo_listing_requests', 'liquidity_pools', 'liquidity_transactions',
  'member_support_tickets', 'merchant_business_ibans', 'merchant_products',
  'pending_profile_changes', 'praeco_peers', 'prepaid_cards', 'private_seed_str_applications',
  'private_seed_str_audit_log', 'profile_changes', 'profiles', 'safe_admins', 'safe_purchases',
  'security_audit_log', 'seed_str_affiliates', 'seed_str_applications', 'seed_str_audit_log',
  'staking_data_cache', 'staking_requests', 'staking_rewards_distribution', 'str_domains',
  'str_dome_requests', 'user_liquidity_positions', 'user_messages', 'user_profiles', 'user_roles',
  'user_staking_pools', 'user_str_shares', 'user_wallets', 'vesting_tokens', 'vip_users',
  'voucher_redemptions', 'wallet_transactions',
];

const WANTED = new Set(
  args[0] && !args[0].startsWith('--')
    ? args[0].split(',').map((s) => s.trim()).filter(Boolean)
    : GAP_TABLES
);

// The file is CRLF; normalise once so every regex below can assume \n.
const src = readFileSync(TYPES_FILE, 'utf8').replace(/\r\n/g, '\n');

// ------------------------------------------------------------ schema facts

/**
 * Ground truth captured read-only from production: per-column type, NOT NULL,
 * DEFAULT, plus CHECK / PRIMARY KEY / UNIQUE constraints and enum labels.
 *
 * Optional by design. Without it the generator degrades to the old inference
 * and says so, which keeps a checkout that has not run the puller usable.
 */
const FACTS_FILE = 'scripts/schema-facts.json';
const facts = existsSync(FACTS_FILE)
  ? JSON.parse(readFileSync(FACTS_FILE, 'utf8'))
  : { tables: {}, checks: {}, keys: {}, enums: {}, _source: null };
if (!facts._source) {
  console.warn(
    `  WARNING: ${FACTS_FILE} not found - falling back to TypeScript inference.\n` +
      '  Column defaults and CHECK constraints will be missing (see F-004).'
  );
}

/** Production facts for one column, or null when the facts do not cover it. */
const factCol = (table, col) => facts.tables?.[table]?.[col] ?? null;

/**
 * Render a production type name as this file must emit it.
 *
 * format_type() drops the schema for anything on the search path, so the six
 * public enums come back bare and would resolve against whatever the replaying
 * session's search_path happens to be. Qualify them explicitly; everything else
 * is a built-in and is emitted verbatim, precision and all.
 */
function factType(t) {
  const bare = t.replace(/\[\]$/, '');
  if (facts.enums?.[bare]) return `public.${bare}${t.endsWith('[]') ? '[]' : ''}`;
  return t;
}

// ----------------------------------------------------------------- enums

/** Parse the `Enums: { name: "a" | "b" }` block into name -> [labels]. */
function parseEnums() {
  const block = src.match(/^    Enums: \{\n([\s\S]*?)\n    \}/m);
  if (!block) return new Map();

  const out = new Map();
  // A definition runs from `name:` to the line before the next `name:`, because
  // long unions are wrapped across many lines by the formatter.
  // Trailing newline so the last entry matches the same shape as the rest.
  const body = block[1] + '\n';
  const re = /^      (\w+):((?:[^\n]*\n(?:        \|[^\n]*\n)*)|[^\n]*\n)/gm;
  for (const m of body.matchAll(re)) {
    const labels = [...m[2].matchAll(/"([^"]*)"/g)].map((x) => x[1]);
    if (labels.length) out.set(m[1], labels);
  }
  return out;
}

// ---------------------------------------------------------------- tables

/**
 * Parse each `tablename: { Row: {...} Insert: {...} Relationships: [...] }`
 * entry. Row gives the column set and nullability, Insert marks which columns
 * have a default (optional on insert), Relationships gives the foreign keys.
 */
function parseTables() {
  const out = new Map();
  const re = /^      (\w+): \{\n        Row: \{\n([\s\S]*?)\n        \}\n        Insert: \{\n([\s\S]*?)\n        \}/gm;

  for (const m of src.matchAll(re)) {
    const [, name, rowBody, insertBody] = m;

    const optional = new Set(
      [...insertBody.matchAll(/^          (\w+)\?:/gm)].map((x) => x[1])
    );

    const cols = [];
    for (const c of rowBody.matchAll(/^          (\w+): (.+)$/gm)) {
      cols.push({ name: c[1], ts: c[2].trim(), hasDefault: optional.has(c[1]) });
    }

    // Relationships block for this table, if the parser can reach it.
    const after = src.slice(m.index + m[0].length);
    const relBlock = after.match(/^        Relationships: \[([\s\S]*?)\n        \]/m);
    const fks = [];
    if (relBlock) {
      for (const r of relBlock[1].matchAll(
        /columns: \["([^"]+)"\][\s\S]*?referencedRelation: "([^"]+)"[\s\S]*?referencedColumns: \["([^"]+)"\]/g
      )) {
        fks.push({ column: r[1], refTable: r[2], refColumn: r[3] });
      }
    }

    out.set(name, { name, cols, fks });
  }
  return out;
}

// ------------------------------------------------------------ type mapping

/**
 * Columns whose Postgres type cannot be recovered from the TypeScript type plus
 * naming alone, corrected against how the migration history actually uses them.
 * Each entry is here because a replay failed on an operator mismatch.
 *
 * All five were re-checked against production on 2026-08-19 and all five are
 * correct, so schema-facts.json now agrees with every one of them. They are
 * kept as the fallback for a checkout with no facts file, and as the record of
 * why these particular columns were ever in doubt.
 */
const TYPE_OVERRIDES = {
  // "Note: user_id is TEXT type, so cast auth.uid() to text" - the migration
  // that adds these policies says so explicitly.
  'praeco_peers.user_id': 'text',
  // Compared against now() in UPDATE ... WHERE payment_deadline < now().
  'seed_str_applications.payment_deadline': 'timestamptz',
  'private_seed_str_applications.payment_deadline': 'timestamptz',

  // Polymorphic audit references, paired with a resource_type column. The
  // log_sensitive_access trigger writes `COALESCE(NEW.id::text, OLD.id::text)`
  // into security_audit_log.resource_id, so that one is text in production.
  // arx_audit_trail follows the same pattern and no writer was found either
  // way; text is chosen because it accepts everything uuid would.
  'security_audit_log.resource_id': 'text',
  'arx_audit_trail.resource_id': 'text',
};

/**
 * Columns the migration history references that the final production shape no
 * longer has - renamed or dropped after the migration that used them was
 * written. The baseline recreates the final shape, so history would break on
 * them; adding them back as nullable lets those migrations replay without
 * changing what the schema converges to.
 */
const LEGACY_COLUMNS = {
  github_integrations: { access_token: 'text' },
  liquidity_pools: {
    base_token: 'text',
    quote_token: 'text',
    // 20250801183118 creates liquidity_pools with these and then reads them
    // back; the final production shape no longer carries them.
    total_liquidity_usd: 'numeric NOT NULL DEFAULT 0',
    apy: 'numeric',
    fee_percentage: 'numeric',
  },
};

/** Map a TypeScript column type + its name onto a Postgres type. */
function pgType(col, enums, table) {
  // Production is the authority when it covers the column. The naming
  // heuristics below are good but not perfect - they read tax_id, tx_id,
  // node_id, processed_by and presented_by as uuid when production has them as
  // text, and last_sync / window_start / last_seen as text when production has
  // them as timestamptz - so anything the facts cover skips them entirely.
  const fact = factCol(table, col.name);
  if (fact) return factType(fact.type);

  const override = TYPE_OVERRIDES[`${table}.${col.name}`];
  if (override) return override;

  const ts = col.ts.replace(/ \| null$/, '').trim();
  const n = col.name;

  const enumRef = ts.match(/Database\["public"\]\["Enums"\]\["(\w+)"\]/);
  if (enumRef) return enums.has(enumRef[1]) ? `public.${enumRef[1]}` : 'text';

  if (ts === 'Json' || ts === 'Json[]') return 'jsonb';
  if (ts === 'number') return n === 'id' ? 'bigint' : 'numeric';
  if (ts === 'boolean') return 'boolean';
  if (ts === 'string[]') return 'text[]';
  if (ts === 'number[]') return 'numeric[]';
  // `unknown` is what the generator emits for types it has no mapping for;
  // in this schema those columns are all inet (ip_address / last_ip).
  if (ts === 'unknown') return 'inet';

  if (ts === 'string') {
    if (n === 'id' || n.endsWith('_id') || n.endsWith('_by') || n === 'uuid') return 'uuid';
    // Any name that reads as a point in time. `_deadline` and `_expires` are
    // here because the history compares them against now().
    if (
      /_(at|date|deadline|expiry|expires|until|time|timestamp|on)$/.test(n) ||
      n === 'timestamp' ||
      n === 'deadline'
    ) {
      return 'timestamptz';
    }
    return 'text';
  }
  return 'text';
}

// ------------------------------------------------- unique constraint recovery

/**
 * Recover UNIQUE constraints from the history's own `ON CONFLICT (cols)`
 * clauses. An upsert only compiles if a matching unique or exclusion constraint
 * exists, so every distinct conflict target is direct evidence of a constraint
 * production has and the types file does not record.
 */
function inferUniqueConstraints(migrationsDir) {
  const found = new Map(); // table -> Set of "col,col"
  let files = [];
  try {
    files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'));
  } catch {
    return found;
  }

  for (const f of files) {
    const sql = readFileSync(join(migrationsDir, f), 'utf8').replace(/\r\n/g, '\n');
    // Split on statement boundaries so a conflict target cannot be attributed
    // to an INSERT in a different statement.
    for (const stmt of sql.split(';')) {
      const target = stmt.match(/INSERT\s+INTO\s+(?:public\.)?(\w+)/i);
      if (!target) continue;
      const conflict = stmt.match(/ON\s+CONFLICT\s*\(([^)]+)\)/i);
      if (!conflict) continue;

      const cols = conflict[1]
        .split(',')
        .map((c) => c.trim().replace(/"/g, ''))
        .filter(Boolean);
      // A conflict target can be an expression; only plain column lists map to
      // a constraint we can safely declare.
      if (!cols.length || cols.some((c) => !/^\w+$/.test(c))) continue;

      if (!found.has(target[1])) found.set(target[1], new Set());
      found.get(target[1]).add(cols.join(','));
    }
  }
  return found;
}

/**
 * Default expression for a column.
 *
 * Production first: `Insert: { x?: ... }` in the types file only says a column
 * is optional on insert, never what value it gets, so the inference below could
 * only ever guess `id` and the two timestamps it recognises by name - 168 of
 * the 421 defaults these tables actually carry. The rest is what F-004 is.
 */
function defaultFor(col, pg, table) {
  const fact = factCol(table, col.name);
  // A generated column carries its expression in the type line, not a DEFAULT.
  if (fact?.generated) return null;
  if (fact) return fact.default ?? null;

  const n = col.name;
  if (n === 'id' && pg === 'uuid') return 'gen_random_uuid()';
  if (pg === 'timestamptz' && (n === 'created_at' || n === 'updated_at')) return 'now()';
  return null;
}

/**
 * Whether a column is NOT NULL.
 *
 * The types file marks nullability with a trailing `| null`, which the
 * generator for `unknown`-typed columns omits - so all ten `ip_address` columns
 * came out NOT NULL here while production has every one of them nullable. That
 * is the same class of defect as the missing defaults, in the other direction:
 * a local database stricter than production.
 */
function isNotNull(col, table) {
  const fact = factCol(table, col.name);
  if (fact) return fact.notnull;
  return !/ \| null$/.test(col.ts);
}

// ------------------------------------------------------------------ emit

const enums = parseEnums();
const tables = parseTables();

// Production's enum labels win where they are known. Checked on 2026-08-19:
// all six types and every label match types.ts exactly, so this changes nothing
// today - it is here so a future divergence is caught by the facts refresh
// rather than by a failing insert.
let enumsFromFacts = 0;
for (const [name, labels] of Object.entries(facts.enums || {})) {
  const before = enums.get(name);
  if (!before || before.join(' ') !== labels.join(' ')) enumsFromFacts++;
  enums.set(name, labels);
}

/**
 * Columns production has that the types file does not.
 *
 * types.ts is regenerated by hand and drifts: it is missing
 * domain_marketplace_listings.category and .image_url, both of which exist in
 * production. The baseline is supposed to reproduce production, so the facts
 * fill the gap rather than the types file capping it.
 */
let factOnlyCols = 0;
for (const [tname, cols] of Object.entries(facts.tables || {})) {
  const t = tables.get(tname);
  if (!t) continue;
  for (const cname of Object.keys(cols)) {
    if (t.cols.some((c) => c.name === cname)) continue;
    t.cols.push({ name: cname, ts: 'string', hasDefault: true, fromFacts: true });
    factOnlyCols++;
  }
}

const found = [...WANTED].filter((t) => tables.has(t));
const absent = [...WANTED].filter((t) => !tables.has(t));

const lines = [];
lines.push('-- Recovered dashboard-created objects.');
lines.push('--');
lines.push('-- These tables and types exist in production but were never created by any');
lines.push('-- migration in this directory - they were made through the Lovable dashboard,');
lines.push('-- so the history references them without ever defining them. Reconstructed');
lines.push(`-- from ${TYPES_FILE}, which is generated from the live database.`);
lines.push('--');
lines.push('-- Shapes are reconstructed, not dumped: later migrations in the history still');
lines.push('-- ALTER these tables, and those ALTERs are what bring them to final form.');
lines.push('');

// Enum types first - tables reference them.
if (enums.size) {
  lines.push('-- Enum types');
  for (const [name, labels] of enums) {
    const vals = labels.map((l) => `'${l.replace(/'/g, "''")}'`).join(', ');
    lines.push(`DO $$ BEGIN`);
    lines.push(`  CREATE TYPE public.${name} AS ENUM (${vals});`);
    lines.push(`EXCEPTION WHEN duplicate_object THEN NULL;`);
    lines.push(`END $$;`);
  }
  lines.push('');
}

lines.push('-- Tables');
let defaultCount = 0;
let defaultsFromFacts = 0;
for (const name of found) {
  const t = tables.get(name);
  const defs = [];

  for (const col of t.cols) {
    const pg = pgType(col, enums, name);
    const notNull = isNotNull(col, name);
    // The `hasDefault` gate only applies to the inference path: it is derived
    // from the Insert block, which is the only hint types.ts gives. When the
    // facts cover the column they already say whether there is a default.
    const def = factCol(name, col.name) || col.hasDefault ? defaultFor(col, pg, name) : null;
    if (def) {
      defaultCount++;
      if (factCol(name, col.name)?.default) defaultsFromFacts++;
    }

    let line = `  "${col.name}" ${pg}`;
    if (def) line += ` DEFAULT ${def}`;
    if (notNull) line += ' NOT NULL';
    defs.push(line);
  }

  // Columns the history still references but the final shape has dropped.
  for (const [lname, ltype] of Object.entries(LEGACY_COLUMNS[name] || {})) {
    if (!t.cols.some((c) => c.name === lname)) {
      // Block comment, not `--`: a line comment here would swallow the comma
      // that separates this column from the next definition.
      defs.push(`  "${lname}" ${ltype} /* legacy: referenced by migration history */`);
    }
  }

  // Production's own primary key where it is known. `PRIMARY KEY (id)` is a
  // good guess but not always right: safe_admins is keyed on user_id, and has
  // no id column at all, so the guess silently left it with no key.
  const pk = (facts.keys?.[name] || []).find((k) => k.kind === 'primary');
  if (pk) {
    defs.push(`  CONSTRAINT ${pk.name} ${pk.def}`);
  } else if (t.cols.some((c) => c.name === 'id')) {
    defs.push('  PRIMARY KEY (id)');
  }

  lines.push(`CREATE TABLE IF NOT EXISTS public.${name} (`);
  lines.push(defs.join(',\n'));
  lines.push(');');

  // CREATE TABLE IF NOT EXISTS does nothing once the table exists, so on a
  // second replay pass it cannot restore a column that a later migration
  // dropped during the first pass. Re-adding every column explicitly makes the
  // baseline self-healing, which is what lets a second pass converge.
  //
  // The DEFAULT is repeated here for the same reason: a column restored on the
  // second pass without its default is exactly the F-004 failure again, one
  // column at a time. NOT NULL is deliberately not repeated - re-adding a
  // column to a table that already has rows would fail on it, and the CREATE
  // above is what establishes it on a clean build.
  for (const col of t.cols) {
    const pg = pgType(col, enums, name);
    const def = factCol(name, col.name) || col.hasDefault ? defaultFor(col, pg, name) : null;
    lines.push(
      `ALTER TABLE public.${name} ADD COLUMN IF NOT EXISTS "${col.name}" ${pg}${def ? ` DEFAULT ${def}` : ''};`
    );
  }
  for (const [lname, ltype] of Object.entries(LEGACY_COLUMNS[name] || {})) {
    lines.push(`ALTER TABLE public.${name} ADD COLUMN IF NOT EXISTS "${lname}" ${ltype};`);
  }
}
lines.push('');

// Unique constraints recovered from ON CONFLICT usage in the history. Emitted
// before the foreign keys because upserts in the history depend on them.
const uniques = inferUniqueConstraints('supabase/migrations');
let uniqueCount = 0;
lines.push('-- Unique constraints, recovered from ON CONFLICT targets in the history');
lines.push('--');
lines.push('-- Emitted for every table with a conflict target, not just the recovered ones:');
lines.push('-- some of these tables are created by a later migration, and the guard makes');
lines.push('-- the statement a no-op until the table and its columns exist.');
for (const [name, colSets] of [...uniques.entries()].sort()) {
  for (const cols of [...colSets].sort()) {
    const cname = `${name}_${cols.replace(/,/g, '_')}_key`.slice(0, 63);
    const colList = cols.split(',').map((c) => `"${c}"`).join(', ');
    lines.push(`DO $$ BEGIN`);
    lines.push(`  ALTER TABLE public.${name} ADD CONSTRAINT ${cname} UNIQUE (${colList});`);
    lines.push(
      `EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;`
    );
    lines.push(`END $$;`);
    uniqueCount++;
  }
}
lines.push('');

// UNIQUE constraints, copied from production.
//
// The ON CONFLICT recovery above finds only the constraints the history happens
// to upsert against, which is a lower bound. Production carries others that
// nothing in the history upserts on - user_profiles.referral_code is UNIQUE
// there and was not here, so the random 8-character default could collide
// locally and nothing would notice.
lines.push('-- UNIQUE constraints, copied from production (scripts/schema-facts.json)');
let factUniqueCount = 0;
for (const name of found) {
  for (const k of facts.keys?.[name] || []) {
    if (k.kind !== 'unique') continue;
    lines.push(`DO $$ BEGIN`);
    lines.push(`  ALTER TABLE public.${name} ADD CONSTRAINT ${k.name} ${k.def};`);
    lines.push(
      `EXCEPTION WHEN duplicate_table OR duplicate_object OR undefined_table OR undefined_column OR unique_violation THEN NULL;`
    );
    lines.push(`END $$;`);
    factUniqueCount++;
  }
}
lines.push('');

// CHECK constraints, copied verbatim from production.
//
// These are the other half of F-004. A status column with a DEFAULT but no
// CHECK accepts values production rejects, so a local test can pass on a write
// the live database would refuse - the mirror image of the missing-default
// problem and just as misleading.
//
// The production constraint NAME is preserved, not a generated one: later
// migrations in the history do `ALTER TABLE ... DROP CONSTRAINT <name>` to
// widen a status list, and a renamed constraint would make those a no-op and
// leave the old, narrower list in force.
lines.push('-- CHECK constraints, copied from production (scripts/schema-facts.json)');
let checkCount = 0;
for (const name of found) {
  for (const c of facts.checks?.[name] || []) {
    lines.push(`DO $$ BEGIN`);
    lines.push(`  ALTER TABLE public.${name} ADD CONSTRAINT ${c.name} ${c.def};`);
    // check_violation covers a constraint added over rows a data migration in
    // the history already inserted; the guard keeps the baseline replayable
    // rather than taking all 64 tables down with one bad row.
    lines.push(
      `EXCEPTION WHEN duplicate_object OR duplicate_table OR undefined_table OR undefined_column OR check_violation THEN NULL;`
    );
    lines.push(`END $$;`);
    checkCount++;
  }
}
lines.push('');


// Row level security for the recovered tables.
//
// The dashboard-created tables carry no RLS of their own - the history never
// creates them, so it never secures them either. Without this the rebuilt
// database leaves 16 tables fully open, including user_roles, where any
// authenticated user could simply insert themselves an admin row. A local
// environment that is more permissive than production is worse than useless
// for testing authorisation, so every recovered table is locked down here.
//
// These are a floor, not a replacement: later migrations add their own
// policies on top, and Postgres ORs permissive policies together.
lines.push('-- Row level security');
let rlsCount = 0;
for (const name of found) {
  const cols = tables.get(name).cols.map((c) => c.name);
  lines.push(`ALTER TABLE public.${name} ENABLE ROW LEVEL SECURITY;`);

  // Role grants must never be writable from the browser. Reads are limited to
  // the caller's own rows; writing is left to SECURITY DEFINER functions and
  // the service role, which bypass RLS.
  if (name === 'user_roles') {
    lines.push(`DO $$ BEGIN
  CREATE POLICY "own roles are readable" ON public.user_roles
    FOR SELECT TO authenticated USING (user_id::text = auth.uid()::text);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;`);
    rlsCount++;
    continue;
  }

  // Anything with a user_id gets owner-scoped READ access, and only read.
  //
  // These policies previously granted INSERT and UPDATE too, which was a
  // serious mistake: Postgres ORs permissive policies together, so a broad
  // "own update" here walked straight past the narrow WITH CHECK clauses the
  // real migrations write on the same tables. A member could PATCH their own
  // arss_balance, fiat balance, staked amount and rewards and get HTTP 200.
  //
  // The consequence was worse than the hole itself: no write-authorisation
  // test run against a local database proved anything about production. A
  // reconstruction must never be more permissive than the thing it stands in
  // for. Reads are scoped so the app is usable; writes are left entirely to
  // the policies the migration history creates.
  if (cols.includes('user_id')) {
    for (const [suffix, cmd, clause] of [
      ['select', 'SELECT', 'USING (user_id::text = auth.uid()::text)'],
    ]) {
      lines.push(`DO $$ BEGIN
  CREATE POLICY "recovered own ${suffix}" ON public.${name}
    FOR ${cmd} TO authenticated ${clause};
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;`);
    }
    rlsCount++;
    continue;
  }

  // No ownership column: readable by signed-in users, writable by nobody from
  // the client. Reference and catalogue tables land here.
  lines.push(`DO $$ BEGIN
  CREATE POLICY "recovered readable" ON public.${name}
    FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;`);
  rlsCount++;
}
lines.push('');

// Foreign keys go last so table creation order does not matter.
lines.push('-- Foreign keys');
for (const name of found) {
  for (const fk of tables.get(name).fks) {
    // auth.users lives outside public; the rest are public tables.
    const refSchema = fk.refTable === 'users' ? 'auth' : 'public';
    const cname = `${name}_${fk.column}_fkey`;
    lines.push(`DO $$ BEGIN`);
    lines.push(`  ALTER TABLE public.${name} ADD CONSTRAINT ${cname}`);
    lines.push(`    FOREIGN KEY (${fk.column}) REFERENCES ${refSchema}.${fk.refTable}(${fk.refColumn}) ON DELETE CASCADE;`);
    // wrong_object_type covers a reference that a later migration turns into a
    // view: on a second pass the target exists but is no longer a table.
    lines.push(
      `EXCEPTION WHEN duplicate_object OR undefined_table OR undefined_column OR wrong_object_type OR invalid_foreign_key THEN NULL;`
    );
    lines.push(`END $$;`);
  }
}
lines.push('');

writeFileSync(OUT, lines.join('\n'));

console.log(`enums      ${enums.size}  (${enumsFromFacts} corrected from production)`);
console.log(`requested  ${WANTED.size}`);
console.log(`recovered  ${found.length}  -> ${OUT}`);
console.log(`facts      ${facts._source ? `${FACTS_FILE} @ ${facts._source.captured_at}` : 'NONE - inference only'}`);
console.log(`columns    ${factOnlyCols} added from production that types.ts omits`);
console.log(`defaults   ${defaultCount}  (${defaultsFromFacts} from production, ${defaultCount - defaultsFromFacts} inferred)`);
console.log(`checks     ${checkCount}  (from production)`);
console.log(`uniques    ${uniqueCount}  (inferred from ON CONFLICT targets) + ${factUniqueCount} from production`);
console.log(`rls        ${rlsCount}  tables secured`);
if (absent.length) {
  console.log(`NOT IN TYPES FILE (${absent.length}): ${absent.join(', ')}`);
}
