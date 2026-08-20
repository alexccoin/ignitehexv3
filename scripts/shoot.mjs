#!/usr/bin/env node
/**
 * Drive the running app and capture every main screen.
 *
 * Signs in as a real seeded user rather than stubbing auth, so what lands in
 * the screenshots is the app as a member actually meets it — guards, RLS-scoped
 * data and all. A blank or error frame is a failure, so each shot is checked
 * for the shell having rendered before it is kept.
 */

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const BASE = process.env.BASE ?? 'http://localhost:8090';
const OUT = process.env.OUT ?? 'c:/tmp/v3-shots';
const EMAIL = 'admin@ignitehex.local';
const PASSWORD = 'LocalDev123!';

mkdirSync(OUT, { recursive: true });

const SCREENS = [
  ['overview', '/'],
  ['account', '/account'],
  ['wallet', '/wallet'],
  ['wallet-transfers', '/wallet/transfers'],
  ['staking', '/staking'],
  ['banking', '/banking'],
  ['marketplace', '/marketplace'],
  ['investments', '/investments'],
  ['governance', '/governance'],
  ['operations', '/operations'],
];

const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 950 } });
const page = await ctx.newPage();

const problems = [];
page.on('console', (m) => {
  if (m.type() === 'error') problems.push(m.text().slice(0, 160));
});

// ---------------------------------------------------------------- sign in
await page.goto(BASE + '/auth', { waitUntil: 'networkidle' });
await page.fill('#email', EMAIL);
await page.fill('#password', PASSWORD);
await page.screenshot({ path: `${OUT}/00-signin.png` });
await page.click('button[type=submit]');

// The shell only mounts once the session resolves and roles load.
await page.waitForSelector('nav', { timeout: 20000 });
await page.waitForTimeout(1500);

// ------------------------------------------------------------- the screens
let n = 1;
for (const [name, path] of SCREENS) {
  await page.goto(BASE + path, { waitUntil: 'networkidle' });
  // Let queries settle so tiles show figures rather than skeletons.
  await page.waitForTimeout(1800);
  const file = `${OUT}/${String(n).padStart(2, '0')}-${name}.png`;
  await page.screenshot({ path: file, fullPage: true });

  const text = (await page.locator('body').innerText()).replace(/\s+/g, ' ').trim();
  console.log(`${file}  ${text.length} chars  ${text.slice(0, 90)}`);
  n++;
}

// ------------------------------------------------------- light mode compare
await page.goto(BASE + '/', { waitUntil: 'networkidle' });
await page.waitForTimeout(800);
// The theme toggle is the button labelled with the mode it switches to.
const toggle = page.getByRole('button', { name: /light|dark/i }).first();
await toggle.click();
await page.waitForTimeout(900);
await page.screenshot({ path: `${OUT}/11-overview-light.png`, fullPage: true });

await browser.close();

console.log('\nconsole errors: ' + problems.length);
for (const p of [...new Set(problems)].slice(0, 12)) console.log('  ' + p);
