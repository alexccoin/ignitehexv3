#!/usr/bin/env node
/**
 * `npm run db:replay` from the repository root.
 *
 * hostless-db.mjs and the two transform scripts it shells out to all resolve
 * their inputs relative to the working directory (`scripts/…`,
 * `supabase/migrations`, `src/integrations/supabase/types.ts`). Vendoring them
 * under db/ without rewriting those paths means the working directory has to be
 * db/ — this sets it, so nobody has to remember, and `cd` stays out of the npm
 * script where it would be shell-dependent.
 *
 * Every argument is forwarded, so `npm run db:replay -- --json report.json`
 * works.
 */

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const dbRoot = join(here, '..');

/**
 * Output paths are resolved against the caller's working directory, not db/.
 * `npm run db:replay -- --json report.json` from the repo root has to write the
 * report where the caller is standing — otherwise it lands in db/ and CI
 * uploads an empty artifact while the file sits somewhere nobody looks.
 */
const argv = process.argv.slice(2);
for (const opt of ['--json', '--out']) {
  const i = argv.indexOf(opt);
  if (i !== -1 && argv[i + 1]) argv[i + 1] = resolve(process.cwd(), argv[i + 1]);
}

const r = spawnSync(process.execPath, [join('scripts', 'hostless-db.mjs'), ...argv], {
  cwd: dbRoot,
  stdio: 'inherit',
});

process.exit(r.status === null ? 2 : r.status);
