#!/usr/bin/env node
/**
 * Make the migration history replayable against a clean database.
 *
 * The history was written against a live database that already had objects in
 * it, so most files assume a state they never create. Replaying them in order
 * on an empty database fails on "already exists" for objects the recovered
 * baseline provides, and on non-idempotent CREATEs when an earlier file in the
 * history made the same object.
 *
 * This rewrites each statement into its idempotent form. It does not change
 * what the schema ends up as - only whether the same file can be applied to a
 * database that already has the object.
 *
 * Data-seeding statements are deliberately left alone. INSERTs written against
 * production rows cannot succeed on an empty database, and rewriting them here
 * turned out to corrupt multi-line statements; the replay driver handles them
 * at run time instead, where it can tell a data error from a schema error.
 *
 * Runs in place. Git holds the originals.
 *
 * Usage: node scripts/repair-migrations.mjs [--dir <dir>] [--dry-run]
 */

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const has = (n) => args.includes(`--${n}`);
const flag = (n, d) => {
  const i = args.indexOf(`--${n}`);
  return i === -1 ? d : args[i + 1];
};

const DIR = flag('dir', 'supabase/migrations');
const DRY = has('dry-run');

const stats = new Map();
const bump = (k, n = 1) => stats.set(k, (stats.get(k) || 0) + n);

/**
 * Blank out comments and string literals so statement-shape regexes cannot
 * match inside them. Returns a mask string of identical length to the source,
 * letting callers test whether an index falls in real code.
 */
function codeMask(sql) {
  const mask = sql.split('');
  let i = 0;
  while (i < sql.length) {
    const two = sql.slice(i, i + 2);
    if (two === '--') {
      while (i < sql.length && sql[i] !== '\n') mask[i++] = ' ';
    } else if (two === '/*') {
      const end = sql.indexOf('*/', i + 2);
      const stop = end === -1 ? sql.length : end + 2;
      while (i < stop) mask[i++] = ' ';
    } else if (sql[i] === "'") {
      mask[i++] = ' ';
      while (i < sql.length) {
        if (sql[i] === "'" && sql[i + 1] === "'") { mask[i++] = ' '; mask[i++] = ' '; continue; }
        if (sql[i] === "'") { mask[i++] = ' '; break; }
        mask[i++] = ' ';
      }
    } else if (sql[i] === '$' && /^\$[A-Za-z_]?\w*\$/.test(sql.slice(i, i + 32))) {
      // Dollar-quoted body, with or without a tag ($$, $function$, $_$ ...).
      // 111 files use a tagged form. Function bodies are replaced wholesale by
      // CREATE OR REPLACE, so nothing inside one should ever be rewritten -
      // masking the whole body is what keeps transforms out of plpgsql.
      const tag = sql.slice(i).match(/^\$[A-Za-z_]?\w*\$/)[0];
      const end = sql.indexOf(tag, i + tag.length);
      const stop = end === -1 ? sql.length : end + tag.length;
      while (i < stop) mask[i++] = ' ';
    } else {
      i++;
    }
  }
  return mask.join('');
}

/**
 * Replace matches of `re` in `sql`, but only where the match starts in real
 * code (per the mask) rather than inside a comment or string.
 *
 * The test is on the match's FIRST character, not on the whole match. Every
 * regex here is anchored on a keyword, so index 0 of a real match is never a
 * blank in the mask; testing the whole span instead let a match that *began*
 * inside a `--` comment and ran on into live code survive, because the live
 * tail kept the slice non-blank. That is the same comment-blindness F-029
 * recorded in the ADD CONSTRAINT transform, one level up.
 *
 * `fn` receives the mask as its second argument, so a callback that needs to
 * look at surrounding text can look at the masked copy rather than the raw one.
 */
function replaceInCode(sql, re, fn, statKey) {
  const mask = codeMask(sql);
  let out = '';
  let last = 0;
  let count = 0;

  for (const m of [...sql.matchAll(re)]) {
    // The mask is index-aligned with the source, so a match whose first
    // character survives in the mask starts in real code.
    if (mask[m.index] === undefined || mask[m.index] === ' ') continue;
    const replacement = fn(m, mask);
    if (replacement === null) continue;
    out += sql.slice(last, m.index) + replacement;
    last = m.index + m[0].length;
    count++;
  }
  out += sql.slice(last);
  if (count && statKey) bump(statKey, count);
  return out;
}

// ------------------------------------------------------------- transforms

function repair(sql) {
  let s = sql;

  // CREATE TABLE -> CREATE TABLE IF NOT EXISTS
  s = replaceInCode(
    s,
    /\bCREATE\s+TABLE\s+(?!IF\s+NOT\s+EXISTS)/gi,
    (m) => m[0].replace(/\s+$/, ' ') + 'IF NOT EXISTS ',
    'CREATE TABLE -> IF NOT EXISTS'
  );

  // ADD COLUMN -> ADD COLUMN IF NOT EXISTS
  s = replaceInCode(
    s,
    /\bADD\s+COLUMN\s+(?!IF\s+NOT\s+EXISTS)/gi,
    (m) => 'ADD COLUMN IF NOT EXISTS ',
    'ADD COLUMN -> IF NOT EXISTS'
  );

  // Bare `ALTER TABLE t ADD <col> <type>` (COLUMN keyword omitted). Anchored on
  // ALTER TABLE so it cannot touch `ALTER TYPE ... ADD VALUE`, and excluding
  // the keywords that introduce a constraint rather than a column.
  s = replaceInCode(
    s,
    /\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?[\w."]+\s+ADD\s+(?!COLUMN|CONSTRAINT|PRIMARY|FOREIGN|UNIQUE|CHECK|EXCLUDE|VALUE|IF\s+NOT\s+EXISTS)(?=[a-z_"][\w"]*\s+[a-z])/gi,
    (m) => m[0].replace(/ADD\s+$/i, 'ADD COLUMN IF NOT EXISTS '),
    'ADD <col> -> ADD COLUMN IF NOT EXISTS'
  );

  // DROP COLUMN / DROP TABLE / DROP INDEX ... -> IF EXISTS
  s = replaceInCode(
    s,
    /\bDROP\s+(COLUMN|TABLE|INDEX|VIEW|SEQUENCE|TYPE|TRIGGER|POLICY|CONSTRAINT)\s+(?!IF\s+EXISTS)/gi,
    (m) => `DROP ${m[1].toUpperCase()} IF EXISTS `,
    'DROP -> IF EXISTS'
  );

  // CREATE [UNIQUE] INDEX -> IF NOT EXISTS
  s = replaceInCode(
    s,
    /\bCREATE\s+(UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS|CONCURRENTLY)/gi,
    (m) => `CREATE ${m[1] ? 'UNIQUE ' : ''}INDEX IF NOT EXISTS `,
    'CREATE INDEX -> IF NOT EXISTS'
  );

  // CREATE FUNCTION -> CREATE OR REPLACE FUNCTION
  s = replaceInCode(
    s,
    /\bCREATE\s+FUNCTION\b/gi,
    () => 'CREATE OR REPLACE FUNCTION',
    'CREATE FUNCTION -> OR REPLACE'
  );

  // CREATE VIEW -> CREATE OR REPLACE VIEW
  s = replaceInCode(
    s,
    /\bCREATE\s+VIEW\b/gi,
    () => 'CREATE OR REPLACE VIEW',
    'CREATE VIEW -> OR REPLACE'
  );

  // CREATE TRIGGER -> CREATE OR REPLACE TRIGGER (Postgres 14+)
  s = replaceInCode(
    s,
    /\bCREATE\s+TRIGGER\b/gi,
    () => 'CREATE OR REPLACE TRIGGER',
    'CREATE TRIGGER -> OR REPLACE'
  );

  // Postgres has no CREATE OR REPLACE POLICY, so drop first. Policy names may
  // be quoted or bare; the table reference may be schema-qualified.
  //
  // `IF NOT EXISTS` is matched and stripped here too: several files use
  // `CREATE POLICY IF NOT EXISTS`, which Postgres has never supported, so those
  // statements were dead on arrival in production as well.
  s = replaceInCode(
    s,
    /\bCREATE\s+POLICY\s+(?:IF\s+NOT\s+EXISTS\s+)?("([^"]+)"|[\w]+)\s+ON\s+([\w.]+)/gi,
    (m, mask) => {
      // Skip when the file already drops this exact policy immediately above,
      // which many of them do - a second identical DROP is just noise.
      //
      // Read the MASKED text, not the raw source. A commented-out
      // `-- DROP POLICY IF EXISTS "x" ON t;` sitting above the CREATE would
      // otherwise be accepted as a real drop, the guard would be suppressed,
      // and the CREATE would fail with "policy already exists" on any second
      // application of the file.
      const before = mask.slice(Math.max(0, m.index - 200), m.index);
      const already = new RegExp(
        `DROP\\s+POLICY\\s+IF\\s+EXISTS\\s+${m[1].replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s+ON\\s+${m[3]}\\s*;\\s*$`,
        'i'
      ).test(before);
      const create = `CREATE POLICY ${m[1]} ON ${m[3]}`;
      return already ? create : `DROP POLICY IF EXISTS ${m[1]} ON ${m[3]};\n${create}`;
    },
    'CREATE POLICY -> DROP + CREATE'
  );

  // CREATE TYPE ... AS ENUM -> guarded, since types have no IF NOT EXISTS.
  // Several files write `CREATE TYPE IF NOT EXISTS`, which Postgres has never
  // accepted; matching it here both fixes the syntax and makes it idempotent.
  //
  // The label list is delimited by scanning for the balanced closing paren and
  // then for the statement's real terminator. The lazy `([\s\S]*?)\)\s*;` this
  // replaced ended the statement at the first `)` that happened to be followed
  // by a semicolon - wherever it sat, including inside a label, inside a
  // comment between labels, or inside a nested paren.
  s = guardStatement(
    s,
    /\bCREATE\s+TYPE\s+(?:IF\s+NOT\s+EXISTS\s+)?([\w.]+)\s+AS\s+ENUM\s*\(/gi,
    (m, body) =>
      `DO $do$ BEGIN\n  CREATE TYPE ${m[1]} AS ENUM ${body};\nEXCEPTION WHEN duplicate_object THEN NULL;\nEND $do$;`,
    'CREATE TYPE -> guarded',
    { fromParen: true }
  );

  // `ALTER PUBLICATION ... ADD TABLE` has no IF NOT EXISTS and errors once the
  // table is already published, which it is on any second pass.
  //
  // `([^;]+);` here was the identical defect to the ADD CONSTRAINT transform
  // below: a semicolon in a trailing comment ended the statement early.
  s = guardStatement(
    s,
    /\bALTER\s+PUBLICATION\s+([\w"]+)\s+ADD\s+TABLE\s+/gi,
    (m, body) =>
      `DO $do$ BEGIN\n  ALTER PUBLICATION ${m[1]} ADD TABLE ${body};\nEXCEPTION WHEN duplicate_object OR undefined_object THEN NULL;\nEND $do$;`,
    'ALTER PUBLICATION -> guarded'
  );

  s = guardCronCalls(s);

  // ADD CONSTRAINT has no IF NOT EXISTS; guard the whole ALTER statement.
  //
  // F-029: this used `([^;]*);` to find the end of the statement, which stops
  // at the first semicolon in the text whether or not that semicolon sits
  // inside a `--` comment, a string literal or a dollar-quoted body. The
  // truncated fragment was then wrapped in a DO block, so the block closed
  // mid-comment and the remainder of the statement was orphaned outside it -
  // `ERROR: unexpected end of function definition at end of input`, in a file
  // that defines no functions. The source file was untouched, so the breakage
  // existed only in the staged copy and was invisible to anyone piping the
  // migration straight into psql. It now delimits the statement with
  // statementEnd(), the scanner guardCronCalls() has used since it hit the
  // mirror image of this bug.
  s = guardStatement(
    s,
    /\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?([\w.]+)\s+ADD\s+CONSTRAINT\s+([\w"]+)/gi,
    (m, body) =>
      `DO $do$ BEGIN\n  ALTER TABLE ${m[1]} ADD CONSTRAINT ${m[2]}${body};\nEXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;\nEND $do$;`,
    'ADD CONSTRAINT -> guarded'
  );

  // pg_cron only installs into pg_catalog; several migrations ask for
  // 'WITH SCHEMA extensions', which Postgres rejects outright. On the hosted
  // project the extension already existed, so IF NOT EXISTS short-circuited and
  // the impossible clause never surfaced. Against a fresh database it does.
  s = replaceInCode(
    s,
    /CREATE\s+EXTENSION\s+(IF\s+NOT\s+EXISTS\s+)?pg_cron\s+WITH\s+SCHEMA\s+\w+/gi,
    (m) => 'CREATE EXTENSION ' + (m[1] ? 'IF NOT EXISTS ' : '') + 'pg_cron WITH SCHEMA pg_catalog',
    'pg_cron -> pg_catalog'
  );

  s = renameReservedVariables(s);
  s = dropSelectTriggerEvents(s);
  return s;
}

/**
 * Wrap a whole statement in a guard, finding its end with the scanner rather
 * than with a character class.
 *
 * `re` matches only the statement's PREFIX - up to the point where the variable
 * part begins. Everything from there to the statement's real terminator is
 * handed to `build` as `body`, with the terminating `;` removed. With
 * `{ fromParen: true }` the prefix must end on an opening paren; the scan jumps
 * to that paren's balanced partner before looking for the terminator, and the
 * paren itself belongs to the body rather than to the prefix.
 *
 * The point of the split is that no regex ever has to express "the rest of the
 * statement". statementEnd() and matchingParen() know about comments, string
 * literals, dollar-quoted bodies and nesting; `[^;]*` knows about none of them.
 */
function guardStatement(sql, re, build, statKey, { fromParen = false } = {}) {
  const mask = codeMask(sql);
  let out = '';
  let last = 0;
  let count = 0;

  for (const m of [...sql.matchAll(re)]) {
    if (mask[m.index] === undefined || mask[m.index] === ' ') continue;
    // matchAll cannot overlap, but a rewritten span can still swallow a later
    // match: `ALTER TABLE t ADD CONSTRAINT a ..., ADD CONSTRAINT b ...;` is one
    // statement with two matches in it. Anything already consumed is skipped,
    // which reproduces what the old `[^;]*;` regex did by accident.
    if (m.index < last) continue;

    let scanFrom = m.index + m[0].length;
    let bodyStart = scanFrom;
    if (fromParen) {
      const open = scanFrom - 1;
      if (sql[open] !== '(') continue;
      const close = matchingParen(sql, open);
      if (close === -1) continue;
      scanFrom = close + 1;
      bodyStart = open;
    }

    const end = statementEnd(sql, scanFrom);
    // statementEnd returns the index just past the `;`, or the end of the file
    // when there is no terminator at all. An unterminated statement is not a
    // statement we can guard, so it is left exactly as it was rather than
    // having a `;` invented for it.
    if (sql[end - 1] !== ';') continue;

    const body = sql.slice(bodyStart, end - 1);
    out += sql.slice(last, m.index) + build(m, body);
    last = end;
    count++;
  }
  out += sql.slice(last);
  if (count && statKey) bump(statKey, count);
  return out;
}

/**
 * Make pg_cron calls non-fatal.
 *
 * pg_cron lives in the `cron` schema on a local stack rather than `extensions`,
 * and unscheduling a job that was never scheduled raises rather than no-ops.
 * Neither affects the schema, so a failure here should not abort the migration.
 *
 * The argument list is found by scanning for the balanced closing paren while
 * tracking dollar-quoted strings. A cron job body is itself SQL wrapped in
 * `$$ ... $$` and routinely contains `);`, so a lazy regex stops inside the body
 * and leaves the dollar quote unterminated.
 */
function guardCronCalls(sql) {
  const mask = codeMask(sql);
  const re = /\bSELECT\s+(?:extensions\.)?cron\.(schedule|unschedule)\s*\(/gi;
  let out = '';
  let last = 0;
  let count = 0;

  for (const m of [...sql.matchAll(re)]) {
    if (mask.slice(m.index, m.index + m[0].length).trim() === '') continue;

    const open = m.index + m[0].length - 1; // index of the '('
    const close = matchingParen(sql, open);
    if (close === -1) continue;

    // Consume through the end of the statement, not just to the closing paren.
    // One file writes `select cron.unschedule(...) where exists (...);` - a
    // trailing clause that would otherwise be left stranded after the guard.
    const end = statementEnd(sql, close + 1);

    const argsText = sql.slice(open + 1, close);
    out +=
      sql.slice(last, m.index) +
      `DO $cron$ BEGIN\n  PERFORM cron.${m[1]}(${argsText});\n` +
      `EXCEPTION WHEN OTHERS THEN\n  RAISE NOTICE 'cron.${m[1]} skipped: %', SQLERRM;\nEND $cron$;`;
    last = end;
    count++;
  }
  out += sql.slice(last);
  if (count) bump('cron.schedule/unschedule -> guarded', count);
  return out;
}

/**
 * If a run of non-code starts at `i`, return the index just past it; otherwise
 * return -1.
 *
 * The four kinds a scanner has to step over are a `--` line comment, a C-style
 * block comment, a single-quoted string (with doubled-quote escapes) and a
 * dollar-quoted body. That is the same set codeMask() blanks. The scanners used
 * to handle only the last two, which is exactly how a semicolon inside a
 * comment came to look like the end of a statement (F-029).
 *
 * Double-quoted identifiers are deliberately NOT stepped over. Handling them
 * would mean one unbalanced `"` anywhere in a file silently swallows the rest
 * of it, and no migration in this history has a quoted identifier containing
 * `;`, `(`, `)` or `--` - measured across all 730 files, 0 hits in real code.
 * (16 raw-text hits exist, every one of them inside a `--` comment or inside a
 * JSON blob in a string literal, and codeMask blanks all 16.)
 */
function skipNonCode(sql, i) {
  const two = sql.slice(i, i + 2);
  if (two === '--') {
    const nl = sql.indexOf('\n', i);
    return nl === -1 ? sql.length : nl + 1;
  }
  if (two === '/*') {
    const end = sql.indexOf('*/', i + 2);
    return end === -1 ? sql.length : end + 2;
  }
  if (sql[i] === "'") {
    let j = i + 1;
    while (j < sql.length) {
      if (sql[j] === "'" && sql[j + 1] === "'") { j += 2; continue; }
      if (sql[j] === "'") return j + 1;
      j++;
    }
    return sql.length;
  }
  if (sql[i] === '$') {
    const dollar = sql.slice(i, i + 32).match(/^\$[A-Za-z_]?\w*\$/);
    if (dollar) {
      const tag = dollar[0];
      const end = sql.indexOf(tag, i + tag.length);
      return end === -1 ? sql.length : end + tag.length;
    }
  }
  return -1;
}

/**
 * Index just past the `;` that ends the statement starting at `from`, ignoring
 * semicolons inside comments, strings, dollar-quoted bodies, or nested parens.
 */
function statementEnd(sql, from) {
  let depth = 0;
  let i = from;
  while (i < sql.length) {
    const skip = skipNonCode(sql, i);
    if (skip !== -1) { i = skip; continue; }
    if (sql[i] === '(') depth++;
    else if (sql[i] === ')') depth--;
    else if (sql[i] === ';' && depth <= 0) return i + 1;
    i++;
  }
  return sql.length;
}

/**
 * Index of the paren closing the one at `open`, skipping comments, strings and
 * dollar-quoted text.
 */
function matchingParen(sql, open) {
  let depth = 0;
  let i = open;
  while (i < sql.length) {
    const skip = skipNonCode(sql, i);
    if (skip !== -1) { i = skip; continue; }
    if (sql[i] === '(') depth++;
    else if (sql[i] === ')') {
      depth--;
      if (depth === 0) return i;
    }
    i++;
  }
  return -1;
}

/**
 * Rename plpgsql variables whose names are reserved SQL keywords.
 *
 * Four migrations declare `current_time TIMESTAMP WITH TIME ZONE := now()`.
 * Postgres parses `current_time` as the keyword, so the declaration is a syntax
 * error, and where it does parse it yields TIME WITH TIME ZONE rather than the
 * intended timestamp - which is where the
 * `timestamp with time zone < time with time zone` failure comes from.
 *
 * The rename is confined to the function body that declares the name, so an
 * unrelated use of the real keyword elsewhere is untouched.
 */
const RESERVED_NAMES = [
  'current_time', 'current_timestamp', 'current_date', 'current_user',
  'current_role', 'session_user', 'localtime', 'localtimestamp',
];

function renameReservedVariables(sql) {
  let count = 0;
  // Walk dollar-quoted bodies; those are the only places a DECLARE can appear.
  const out = sql.replace(/(\$[A-Za-z_]?\w*\$)([\s\S]*?)\1/g, (whole, tag, body) => {
    let patched = body;
    for (const name of RESERVED_NAMES) {
      // Only rewrite when the body actually declares it as a variable:
      // `<name> <type> :=` or `<name> <type>;` in a DECLARE section.
      const declares = new RegExp(`^\\s*${name}\\s+[A-Za-z]`, 'im').test(body);
      if (!declares) continue;
      patched = patched.replace(new RegExp(`\\b${name}\\b`, 'gi'), `v_${name}`);
      count++;
    }
    return tag + patched + tag;
  });
  if (count) bump('reserved plpgsql variable renamed', count);
  return out;
}

/**
 * Strip SELECT from trigger event lists.
 *
 * One migration writes `AFTER SELECT OR INSERT OR UPDATE OR DELETE`. Postgres
 * has no SELECT triggers, so the statement has never been valid; the other
 * events are kept so the audit trigger still does its job.
 */
function dropSelectTriggerEvents(sql) {
  return replaceInCode(
    sql,
    /\b(AFTER|BEFORE)\s+SELECT\s+OR\s+/gi,
    (m) => `${m[1].toUpperCase()} `,
    'trigger: SELECT event removed'
  );
}

// ------------------------------------------------------------------- main

const files = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort();
let changed = 0;

for (const file of files) {
  const path = join(DIR, file);
  const original = readFileSync(path, 'utf8');

  const out = repair(original);

  if (out !== original) {
    changed++;
    if (!DRY) writeFileSync(path, out);
  }
}

console.log(`\n  Migration repair${DRY ? ' (dry run)' : ''}`);
console.log('  ' + '─'.repeat(52));
console.log(`  files scanned   ${files.length}`);
console.log(`  files changed   ${changed}\n`);
for (const [k, v] of [...stats.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(v).padStart(5)}x  ${k}`);
}
console.log('');
