# IgniteHeX / SourceLess — Platform Business Rules (V1 legacy)

**Purpose.** The authoritative, source-cited extraction of every business rule in the V1 legacy
platform: assets, staking, rewards, withdrawals, minting, tiers, fees and invariants. This document
is a *description of what the system actually does*, not of what it was supposed to do. Where the
two differ, the difference is recorded in §I.

**Extraction date:** 2026-08-18.

**Sources and how they are cited:**

| Tag in citations | What it is |
|---|---|
| `db:<function_name>` | Body of a `public` schema function read out of the live local rebuild via `pg_get_functiondef` / `prosrc` |
| `db:<table>` | Live `information_schema` / `pg_constraint` / `pg_policies` / `pg_trigger` state of the rebuilt DB |
| `mig:<filename>[:line]` | `supabase/migrations/<filename>` in `C:/Users/strho/hex-ignite-nexus/supabase/migrations` (identical set replayed into the local DB) |
| `fn:<name>/index.ts:line` | `supabase/functions/<name>/index.ts` (V1 edge functions) |
| `v1:<path>:line` | `C:/Users/strho/hex-ignite-nexus/src/<path>` |
| `v2:<path>:line` | `c:/tmp/ignitehex-v2/src/<path>` |
| `audit:§n` | `C:/Users/strho/hex-ignite-nexus/docs/MASTER_AUDIT.md` — owner-supplied ground truth and live forensics |
| `cron` | `cron.job` table of the local DB |

### Reliability caveat on the local database

The local database (`supabase_db_dbtest`) is a **migration replay plus a synthesised "recovered
schema"**, not a production dump. Two consequences, both load-bearing:

1. **RLS in the local DB is NOT production RLS.** `mig:20250720000000_recovered_dashboard_objects.sql`
   is a reconstruction written by `scripts/gen-recovered-schema.mjs`, and that generator emits
   blanket `CREATE POLICY "recovered own <cmd>"` policies (`scripts/gen-recovered-schema.mjs:402` in
   the v2 tree). Those policies survive the production lockdown migration
   `mig:20260509121934_8c0a9f7f-e701-4bb1-abba-692093165f29.sql:11-13`, because that migration drops
   policies *by name* (`"Users can insert their own staking pools"`), and the recovered policies have
   different names. So the local DB shows `user_staking_pools` as user-writable when production is
   not. **Never read authorization rules off the local DB.** RLS statements in this document are
   sourced from migrations only.
2. **Function `EXECUTE` grants in the local DB are NOT production grants.** The rebuild script ends
   with a blanket `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated,
   service_role` (`c:/tmp/ignitehex-v2/scripts/rebuild-local.mjs:83`), which re-grants everything any
   migration revoked. Grant statements in this document are sourced from migrations only.
3. **`enhanced_staking_pools` row data IS real** — it is seeded by migrations
   (`mig:20250903045926:217`, `mig:20251001051536`, `mig:20251001053005`) and is therefore authoritative.
4. **Table shape can differ from what a migration declares.** `mig:20250720000000_recovered_dashboard_objects.sql`
   creates most tables with `CREATE TABLE IF NOT EXISTS`; a *later* migration that re-declares the same
   table with `CREATE TABLE IF NOT EXISTS … CHECK (…)` is then a **no-op**, and its CHECK constraints
   never exist. This is not merely a local artifact — the same ordering held in production, which is
   why that recovery file was needed at all. Wherever a declared constraint is absent from
   `pg_constraint`, this document reports the *effective* state and names the migration that believed
   otherwise.

### Post-V1 remediation already staged (not part of the V1 ruleset)

Two migrations dated 2026-08-18 exist in the v2 tree only and are *forward* fixes, not legacy rules.
They are excluded from §A–§H and noted here so they are not mistaken for V1 behaviour:
`c:/tmp/ignitehex-v2/supabase/migrations/20260818120000_v3_risk_closure.sql:23-26` revokes PUBLIC /
`anon` / `authenticated` EXECUTE on `distribute_enhanced_rewards` and adds `assert_caller_owns`;
`…/20260818120100_v3_guard_debit_functions.sql:30-43` actually wires that guard into
`debit_fiat_wallet` and `debit_staking_pool_balance`, which the first migration created but never
called.

---

## A. ASSETS

### A.1 The asset register

| Symbol | What it represents | Max supply / cap | Cap enforced? | Decimal precision | Where the balance lives |
|---|---|---|---|---|---|
| **STR** | Native settlement/gas token, bound to a `str.domain` identity | **63,000,000,000** (owner ground truth, `audit:§2`; UI restates it at `v1:pages/CCoinBankPro.tsx:618`) | **NO** — no constraint, trigger, or code path anywhere (§H) | `numeric`, unconstrained scale | `user_staking_pools.balance` / `.staked_amount` where `pool_type='str'` (`db:user_staking_pools`) |
| **wSTR** | "Wrapped STR" — the cashable reward token. *All* staking rewards are paid in wSTR regardless of the staked token (`mig:20251130074027:65,80`) | none defined | n/a | `numeric` | **Three different stores, no single source of truth** (see §I-2): `arss_transactions` rows (`db:get_user_wstr_balance`); `user_staking_pools.balance` where `pool_type='wstr'`; `user_staking_pools.rewards_earned` on any pool |
| **CCOS** | Scarce reserve asset; holding it unlocks the 0.00% CCoin Bank settlement tier | **63,000,000** (owner ground truth, `audit:§2`; UI at `v1:pages/CCoinBankPro.tsx:621`, `v2:pages/FounderPool.tsx:1442`) | **NO** (§H). Live breach measured at **1,026,018,564 held = 16.3×** (`audit:§3.1`) | `numeric` | `user_staking_pools` where `pool_type='ccos'`; CCoin Bank balances in `crypto_wallets` (`token_type='CCOS'`) |
| **ARSS** | Utility/AI-credit token; 1,000 granted free at signup | none defined | n/a | `numeric` | `user_wallets.arss_balance` (`db:user_wallets`) **and** `user_staking_pools` where `pool_type='arss'` — two independent stores |
| **DOMAIN** | Staked `str.domain` name records treated as a fungible pool balance | none defined | n/a | `numeric` | `user_staking_pools` where `pool_type='domain'`; the domain records themselves in `str_domains` |
| **eSTR** | Declared pool type; no rate table, no price, no issuance path found | — | — | `numeric` | `user_staking_pools` where `pool_type='estr'` |
| **STR$ / str_stable** | USD-pegged stable unit (1:1); minted 1:1 with USD on STARW node purchase (`v2:pages/StarwSale.tsx:395`) | none | — | `numeric` | `user_staking_pools` where `pool_type='str_stable'` |
| **CCOIN** | CCoin Network internal transfer unit | none | — | `numeric` | `ccoin_ledger.amount`, default currency `'CCOIN'` (`db:ccoin_ledger`) |
| Fiat EUR/USD/CHF/GBP | Withdrawable fiat produced by wSTR conversion | none | — | `numeric` | `fiat_wallets.balance` / `.available_balance` / `.held_balance` |

The canonical pool-type list is enforced:
`CHECK (pool_type = ANY (ARRAY['str','ccos','domain','arss','wstr','estr','str_stable']))`
— `db:user_staking_pools_pool_type_check`. Seven pools (one per type, 3-month duration) are auto-created
for every user by `db:initialize_user_staking_pools` and the `trigger_auto_create_staking_pools` /
`auto_init_str_stable_pool` triggers on `user_profiles`.

Voucher redemption accepts only four token types:
`CHECK (token_type = ANY (ARRAY['str','ccos','arss','vanquish']))` — `db:voucher_redemptions_token_type_check`.
**`vanquish` is a fifth asset accepted by the voucher table that has no pool type, no price, and no
crediting branch in `db:credit_voucher_tokens`** (§I).

POS accepts only `STR, wSTR, CCOS, ARSS` — `db:pos_transactions_currency_check`.

### A.2 Decimal precision

There is **no fixed-point discipline anywhere.** Every money column is bare `numeric` with no
precision/scale. Two separate and mutually incompatible conventions exist in code:

| Convention | Where | Citation |
|---|---|---|
| Raw units, `numeric` | All DB functions and edge functions | `db:user_staking_pools` |
| Micro-units (`× 1e6`) | v2 frontend converter | `v2:lib/tokenUtils.ts:14,32,44-45,54` |
| IEEE-754 `float` on money | `process-swap`, `manual-rewards-distribution`, `convert-wstr-to-fiat`, `process-fiat-transfer` | `audit:§5.4 (B7/R8)` |

---

## B. STAKING POOL RULES

### B.1 Pool model

Two overlapping models coexist:

| Model | Definition table | Per-user rows | Introduced |
|---|---|---|---|
| **Basic pools** | none — pool type is a text column | `user_staking_pools` (`is_enhanced_pool=false`) | original |
| **Enhanced pools** | `enhanced_staking_pools` (18 rows) | `user_staking_pools` with `is_enhanced_pool=true`, `enhanced_pool_id` FK | `mig:20250903045926` |

Allowed durations are constrained on the *request*, not the pool:
`CHECK (duration_months = ANY (ARRAY[3,6,9,12,24,36,48]))` — `db:staking_requests_duration_check`,
matched by the edge-function schema `z.enum(['3','6','9','12','24','36','48'])` at
`fn:submit-staking-request/index.ts:17`.
Domain staking additionally rejects 3 months server-side (`fn:submit-staking-request/index.ts:153-160`).

### B.2 The authoritative pool table (`enhanced_staking_pools`, live rows)

Query: `select name, token_type, duration_months, apr_min, apr_max, min_stake_amount, max_stake_amount, status, reward_curve from enhanced_staking_pools`.

| name | token | months | apr_min | apr_max | min stake | max stake | status | reward_curve |
|---|---|---|---|---|---|---|---|---|
| CCOS Spark Pool | ccos | 3 | 12.5 | 14.5 | 1000 | 10,000,000 | **NULL** | NULL |
| CCOS Pulse Vault | ccos | 6 | 15 | 17.5 | 1000 | 10,000,000 | **NULL** | NULL |
| CCOS Momentum Lock | ccos | 12 | 20 | 24 | 1000 | 10,000,000 | **NULL** | NULL |
| CCOS Gravity Stake | ccos | 24 | 30 | 37 | 1000 | 10,000,000 | **NULL** | NULL |
| CCOS Eclipse Reserve | ccos | 48 | 67 | 77 | 1000 | 10,000,000 | **NULL** | NULL |
| Domain Spark Pool | domain | 3 | 13 | 15 | 100 | 1,000,000 | **NULL** | NULL |
| Domain Pulse Vault | domain | 6 | 16 | 18.5 | 100 | 1,000,000 | **NULL** | NULL |
| DOMAIN 9m Enhanced | domain | 9 | 13.0 | 13.0 | 0 | 10,000,000 | active | linear |
| Domain Momentum Lock | domain | 12 | 21 | 25 | 100 | 1,000,000 | **NULL** | NULL |
| Domain Gravity Stake | domain | 24 | 32 | 39 | 100 | 1,000,000 | **NULL** | NULL |
| DOMAIN 36m Enhanced | domain | 36 | 22.0 | 22.0 | 0 | 10,000,000 | active | linear |
| Domain Eclipse Reserve | domain | 48 | 70 | 80 | 100 | 1,000,000 | **NULL** | NULL |
| STR Spark Pool | str | 3 | 11 | 13 | 1000 | 10,000,000 | **NULL** | NULL |
| STR Pulse Vault | str | 6 | 13.5 | 16 | 1000 | 10,000,000 | **NULL** | NULL |
| STR Momentum Lock | str | 12 | 18 | 22 | 1000 | 10,000,000 | **NULL** | NULL |
| STR Gravity Stake | str | 24 | 28 | 35 | 1000 | 10,000,000 | **NULL** | NULL |
| STR Nova Stake | str | 36 | 50.00 | 60.00 | **50,000** | 10,000,000 | active | NULL |
| STR Eclipse Reserve | str | 48 | 65 | 75 | 1000 | 10,000,000 | **NULL** | NULL |

Seed sources, in order:
`mig:20250903045926_9207c604…:217` seeds the 15 `Spark / Pulse / Momentum / Gravity / Eclipse` rows
across STR, CCOS and DOMAIN — **setting no `status`, no `reward_curve`, no `tvl_cap`**, which is why
those columns are NULL;
`mig:20250903050137_f80e4dd5…:2` re-runs that seed **byte-identically** (a duplicated migration);
`mig:20251001051536_0abc7f14…:6-31` adds `STR Nova Stake` with `status='active'`;
`mig:20251001053005_58b0d569…:2-44` adds a `defs` CTE guarded by
`WHERE NOT EXISTS (… token_type, duration_months)`, so only the two rows with no pre-existing
(token, duration) pair survive — `DOMAIN 9m Enhanced` and `DOMAIN 36m Enhanced`. Its intended STR
3/6/12/24/36/48 rows at 13/16/22/35/60/75 were all skipped.
A fifth site, `mig:20250903060300_e44b965e…:43`, creates pools *at migration time* from live user
data with `apr_min = apy_rate × 0.8` and `apr_max = apy_rate × 1.2` — machine-generated bands with no
product meaning.

**Critical:** 16 of 18 rows have `status = NULL`, not `'active'`. Every consumer filters on
`status = 'active'`:
- `db:distribute_enhanced_rewards` (2025-09-03 version, `mig:20250903045926:46`)
- `db:process_staking_request` fallback branch (`… AND esp.status = 'active'`)
- the RLS read policy on `enhanced_staking_pools` (`db:pg_policies`)

so those 16 pools are invisible and unusable. There is **no CCOS 6/9/36-month pool, no ARSS pool,
no wSTR pool, and no eSTR pool at all**, even though all four are legal `pool_type` values.

`tvl_cap`, `compounding`, `whitelist_only`, `start_date`, `end_date` exist as columns and are
**never read or written by any migration, function, edge function, or frontend file** (grep over all
three trees returns only the DDL and the generated TypeScript type).

### B.3 The nine conflicting APY schedules (server side)

There are **nine** independent APY tables inside the database alone, plus six more in the frontend
(§B.4). Nothing reconciles any of them.

**(1) `db:update_pool_apy_by_duration` — the rate that is actually written onto user pools.**
Latest definition `mig:20251218042835_b1899973…` (also `mig:20251106065953:114-145`). It rewrites
`user_staking_pools.apy_rate` and `.dynamic_apy` in place.

| duration | **str** | **ccos** | **domain** | arss | other |
|---|---|---|---|---|---|
| ≥48 | 70.0 | 76.25 | 82.5 | 70.0 | 12.0 |
| ≥36 | 46.0 | 52.0 | 57.5 | 46.0 | 12.0 |
| ≥24 | 31.5 | 35.75 | 40.0 | 31.5 | 12.0 |
| ≥12 | 20.0 | 22.5 | 25.0 | 20.0 | 12.0 |
| ≥9 | 14.75 | 16.5 | **21.5** | 14.75 | 12.0 |
| ≥6 | 14.75 | 16.5 | 18.0 | 14.75 | 12.0 |
| else (3) | **12.0** | 13.5 | 18.0 | 12.0 | 12.0 |

(The `arss` branch exists only in the `mig:20251218042835` copy inside
`process_staking_request(uuid,text,text)`; `update_pool_apy_by_duration` itself falls through to `12.0`.)

**(2) `db:calculate_dynamic_apy` — the rate the enhanced-stake path actually assigns.**
`base_apy := 11.0`, multiplied by a duration multiplier and a network-efficiency factor clamped to
`[0.5, 1.5]`, then capped at `90.0`:

| duration | multiplier | APY at efficiency 1.0 |
|---|---|---|
| ≥48 | 6.0 | 66.0 |
| ≥36 | 4.5 | 49.5 |
| ≥24 | 3.0 | 33.0 |
| ≥12 | 2.0 | 22.0 |
| ≥6 | 1.4 | 15.4 |
| else | 1.0 | 11.0 |

It is **token-blind** — the body comments `-- Base APY rates by token type (assuming STR for now)`
and then ignores `token_type` entirely. A CCOS or DOMAIN enhanced stake gets the STR curve.
`db:distribute_enhanced_rewards` calls this and writes the result to both `apy_rate` and `dynamic_apy`.

**(3) `db:calculate_staking_rewards` — a third, much lower table, in *fractions* not percent.**

| duration | value | note |
|---|---|---|
| 3 | `0.05` | |
| 6 | `0.10` | |
| 12 | `0.20` | |
| anything else | `0` | 9, 24, 36, 48 months earn **zero** |

The body computes `v_rewards := (v_balance * v_apy) / 365` — no `/100`. So `0.20` here means 20%,
i.e. the same convention as a percentage already divided by 100, while every other function stores
`20.0` and divides by 100. Two functions with the same name-shape use incompatible units.
This function reads `balance` (principal **+** accrued rewards), not `staked_amount`.

**(4) `enhanced_staking_pools.apr_min/apr_max`** — the table in §B.2. Ranges, not points.
`mig:20251001053005:47-65` writes `apy_rate = esp.apr_max` (always the top of the band) onto user pools.

**(5) Voucher APY** — `db:credit_voucher_tokens`: `str → 13.0`, `ccos → 13.0`, `arss → 12.0`,
anything else `0.0`. Applied only when the target pool's existing `apy_rate` is 0.

**(6) Pre-CEX STR voucher pools — 0% APY, hard-locked.** `db:credit_voucher_tokens` creates a
dedicated pool with `apy_rate = 0`, `dynamic_apy = 0`, `lock_end_date = NOW() + 60 days`,
`admin_notes` prefixed `precex_str_voucher_60d_vesting:`.

**(7) A duration-only, token-blind table.** `mig:20250929154826:147`, repeated in
`mig:20251001043630`, `20251001043652`, `20251001043750` (all `:104-118`), `mig:20251001054627:66`
and `mig:20251001055111 / 055129 / 055144 / 055449` (all `:77`):

| 3 | 6 | 9 | 12 | 24 | 36 | 48 |
|---|---|---|---|---|---|---|
| 11.0 | 13.0 | 14.0 *(only in the `1001055*` copies)* | 15.0 | 18.0 | 22.0 | 25.0 |

**(8) A much lower table, briefly canonical.** `mig:20251207055432_8fea15b5…:32-67`, installed on the
`process_staking_request(uuid,text,text)` overload eleven days before it was overwritten:

| duration | str | ccos | domain |
|---|---|---|---|
| 3 | 5.0 | 6.0 | 4.0 |
| 6 | 7.5 | 9.0 | 6.0 |
| 9 | 10.0 | 12.0 | 8.0 |
| 12 | 12.5 | 15.0 | 10.0 |
| 24 | 15.0 | 18.0 | 12.0 |
| 36 | 17.5 | 21.0 | 14.0 |
| 48 | 20.0 | 24.0 | 16.0 |

Any pool approved through that overload between 2025-12-07 and 2025-12-18 carries these rates —
roughly **a quarter** of the rates schedule (1) assigns for the same duration — and nothing has ever
re-normalised them.

**(9) A one-off data UPDATE that overwrote rows directly.** `mig:20251218042415_c4b3c25e…:6-15`:

```sql
UPDATE user_staking_pools SET apy_rate = CASE stake_duration_months
  WHEN 3 THEN 5  WHEN 6 THEN 10 WHEN 9 THEN 15 WHEN 12 THEN 20
  WHEN 24 THEN 25 WHEN 36 THEN 30 WHEN 48 THEN 35 ELSE 10 END
WHERE pool_type = 'domain' AND apy_rate = 0 AND staked_amount > 0;
```

It ran *hours before* `mig:20251218042835` re-declared schedule (1), and it wrote **rows**, not a
function — so those values survive. Domain 48-month pools touched by it pay **35%**; schedule (1)
says **82.5%** for the same pool.

Two later backfills add yet more one-off row writes: `mig:20260106060850:335`
(`apy_rate = CASE WHEN pool_type='arss' THEN 12.0 ELSE 13.0 END` for 3-month zero-APY pools) and
`mig:20260126063204:9` (`apy_rate = 20` for Seed-STR users).

### B.4 The frontend's own tables (all six of them)

None of these agree with the DB, or with each other.

| # | Source | STR 3/6/12/24/36/48 | Citation |
|---|---|---|---|
| UI-1 | `SuperAdminDash` `APY_RATES` | **15 / 20 / 30 / 45 / — / 60** (as fractions `0.15…0.60`) | `v2:pages/SuperAdminDash.tsx:57-64` |
| UI-2 | `StakingForm.getLockPeriods()` | 11–13 / 13.5–16 / 18–22 / 28–35 / 42–50 / 65–75 | `v2:components/StakingForm.tsx:138-143` |
| UI-3 | `StakingCalculator` predefined pools | 11–13 / 13.5–16 / 18–22 / 28–35 / — / 65–75 (+ 26-month and 122-month pools) | `v2:components/StakingCalculator.tsx:15-23` |
| UI-4 | `PoolDeploymentSection` | 11–13 / 13.5–16 / 18–22 / 28–35 / 42–50 / 65–75 | `v2:components/PoolDeploymentSection.tsx:159-274` |
| UI-5 | `PoolSplittingManager` (text) | 11 / 13 / 15 / 18 / 22 / 25 | `v2:components/PoolSplittingManager.tsx:77` |
| UI-6 | `StakingWithdrawals` mock pools | wstr 12.0, domain 13.0, btc 6.8, eth 8.5, bnb 7.2 — fabricated rows merged into real user data | `v2:pages/StakingWithdrawals.tsx:160-166,168` |

`SuperAdminDash` has no 9-month or 36-month entry and falls back to `|| 0`
(`v2:pages/SuperAdminDash.tsx:82`), so admins see 9- and 36-month stakes as earning nothing.

The 15/20/30/45/60 STR table named in the extraction brief is **confirmed** and lives only at
`v2:pages/SuperAdminDash.tsx:58-64`. The DB pays 12 / 14.75 / 20 / 31.5 / 46 / 70 for the same
durations (`db:update_pool_apy_by_duration`) — so the admin console over-reports 3-month STR by
25% and under-reports 48-month STR by 14%, while 36-month reads as 0 against an actual 46%.

### B.5 Min / max stake

| Rule | Value | Where | Enforced? |
|---|---|---|---|
| Per-request maximum | 1,000,000,000 | `fn:submit-staking-request/index.ts:16` | Server-side (Zod) — but only on this one path |
| Per-request minimum | none (`min="0"`, `step="0.000001"`) | `v2:components/StakingForm.tsx:406-407` | no |
| Pool `min_stake_amount` | 0 / 100 / 1000 / 50000 (§B.2) | `enhanced_staking_pools` | **Only in the 2025-09-03 version** of `distribute_enhanced_rewards` (`mig:20250903045926:57-60`). The live version (`mig:20250929031813`) **dropped the check entirely** |
| Pool `max_stake_amount` | 1,000,000 / 10,000,000 | `enhanced_staking_pools` | **Never checked by any code** |
| Calculator constants | `MIN_STAKE = 10`, `MAX_STAKE = 10_000_000` | `v2:components/StakingCalculator.tsx:12-13` | UI only |
| Calculator copy | "Minimum stake amount is 1,000 STR", `min="1000"` | `v2:components/StakingCalculator.tsx:104,143` | UI only, and contradicts `MIN_STAKE = 10` on line 12 which is also the APY-interpolation denominator (`:28`) |
| Absolute pool ceiling | `balance > 999999999999999` rejected | `db:validate_staking_balance` via trigger `validate_staking_balance_trigger` | **YES** — real DB trigger |

---

## C. REWARD MECHANICS

### C.1 Scheduled jobs (`cron.job`)

| jobname | schedule | invokes | Ultimately runs |
|---|---|---|---|
| `daily-staking-rewards` | `0 0 * * *` | `POST /functions/v1/calculate-daily-rewards` | `db:distribute_vested_rewards` via `fn:calculate-daily-rewards/index.ts:155` |
| `starw-daily-wstr-rewards` | `0 0 * * *` | `POST /functions/v1/starw-daily-rewards` | `db:distribute_starw_wstr_rewards` (`fn:starw-daily-rewards/index.ts:45`) |
| `supernode-daily-wstr-rewards` | `0 0 * * *` | `POST /functions/v1/supernode-daily-rewards` | `db:distribute_supernode_wstr_rewards` (`fn:supernode-daily-rewards/index.ts:43`) |
| `release-expired-domain-reservations` | `0 * * * *` | `POST /functions/v1/release-expired-reservations` | domain reservation expiry |
| `daily-backup-0300utc` | `0 3 * * *` | `POST /functions/v1/daily-backup` | backup |

All five cron entries embed a **hardcoded production anon JWT in the job command** (`cron`).

### C.2 Reward formulas, one by one

| Function | Formula | Reads | Writes | Cadence | Gating |
|---|---|---|---|---|---|
| **`db:distribute_vested_rewards`** (`mig:20251130074027:4-101`) | `daily = staked_amount × effective_apy / 100 / 365`; `total = daily × days_to_credit` where `days_to_credit = GREATEST(1, today − last_reward_date)` (or `today − created_at::date` if never rewarded) | `staked_amount`, `COALESCE(dynamic_apy, apy_rate)` | `user_staking_pools.rewards_earned += total`, `.balance += total`, `.last_reward_date = today`; **and** an `arss_transactions` row `transaction_type='staking_reward'`, `currency='wSTR'` | 00:00 UTC daily, plus every admin click | `staked_amount>0 AND apy_rate>0 AND status='active' AND created_at < now()−1d AND (last_reward_date IS NULL OR < today) AND (lock_end_date IS NULL OR > now())` |
| **`db:calculate_daily_rewards`** (legacy, `db`) | `daily = balance × apy_rate / 100 / 365` — **compounds on `balance`, which already includes prior rewards** | `balance` | `rewards_earned += daily`, `balance += daily`, plus an `arss_transactions` row with `transaction_type = 'earn'` | RPC-reachable; wrapped by `db:manual_calculate_rewards` | `balance>0 AND user_profiles.status='approved' AND created_at ≤ now()−24h`. **No `last_reward_date` guard, no lock-end guard** |
| **`db:backfill_historical_rewards`** (`mig:20251130074246:4-104`) | `expected_total = staked × apy/100/365 × days_since_creation`; `missing = expected_total − rewards_earned`; credits `missing` if `> 0.01` | `staked_amount`, effective APY, `rewards_earned` | `rewards_earned = expected_total` (**assignment, not increment**), `balance += missing`, `last_reward_date = today`, plus an `arss_transactions` `staking_reward` row | manual only | same as vested, minus the `last_reward_date` filter |
| **`db:distribute_starw_wstr_rewards`** (`mig:20260322052154:50-86`) | **flat `2.9` wSTR per active STARW node per day** | `starw_nodes` | `starw_wstr_rewards` **only** | 00:00 UTC daily | `status='active'` + `NOT EXISTS (same node, same date)` → idempotent per day |
| **`db:distribute_supernode_wstr_rewards`** (`mig:20260322053054:57-92`) | **flat `27.7` wSTR per active supernode per day** | `supernodes` | `supernode_wstr_rewards` **only** | 00:00 UTC daily | same idempotency guard |
| **`db:calculate_contribution_reward`** | `base × (quality_score/50) × LEAST(2.0, content_size/1000)` where base = text 10 / image 15 / document 25 / code 30 / else 5 | args | returns a value; no writer found | n/a | none |
| **`fn:manual-rewards-distribution`** | `daily = staked × apy / 100 / 365` (`:288`) | `user_staking_pools` | `user_staking_pools` + `arss_transactions` | admin button | `status='active' AND apy_rate>0` (`:188-190`, `:210-212`) — **no `lock_end_date` gate** |

### C.3 Where rewards land, and whether they are spendable

| Store | Written by | Counted as spendable wSTR? |
|---|---|---|
| `arss_transactions` (`transaction_type='staking_reward'`) | vested, backfill, manual | **Yes** — summed by `db:get_user_wstr_balance` |
| `user_staking_pools.balance` | vested, backfill, legacy daily, manual | **Yes, separately** — spendable via `db:debit_staking_pool_balance` and `db:transfer_staking_pool_atomic` |
| `user_staking_pools.rewards_earned` | same | Displayed as wSTR by the dashboard, but is a *third* number (`audit:§5.3 R2b`) |
| `starw_wstr_rewards` | STARW cron | **No** — no reader, no conversion path (`audit:§3.9`, ~16,194 wSTR stranded) |
| `supernode_wstr_rewards` | supernode cron | **No** — ~77,422 wSTR stranded (`audit:§3.9`) |
| `arss_transactions` with `transaction_type='earn'` | `db:calculate_daily_rewards` | **No** — `'earn'` is not in the summed set (§C.4) |

### C.4 The canonical wSTR balance definition

`db:get_user_wstr_balance` (`mig:20251101122302:57-79`), replicated verbatim inside
`db:convert_wstr_to_fiat_atomic`:

```
+ amount  WHEN transaction_type IN ('credit','staking_reward','airdrop','purchase','manual_credit','voucher_credit')
- amount  WHEN transaction_type IN ('debit','withdrawal','transfer_out')
  0       ELSE
```

Every other `transaction_type` is silently ignored. Types written elsewhere in the system that fall
into the `ELSE` branch and therefore **do nothing**:

| Type | Written by | Effect |
|---|---|---|
| `earn` | `db:calculate_daily_rewards` | user is under-credited |
| `stake` | `db:distribute_enhanced_rewards` | no effect (arguably correct) |
| `voucher_redemption` | `db:credit_voucher_tokens` | **voucher tokens never reach the wSTR balance** |
| `balance_correction`, `admin_correction`, `voucher_correction`, `migration_correction`, `staking_reward_correction` | every `fix_*` / `correct_*` path | **−9,396,884,459 wSTR of clawbacks with zero effect** (`audit:§3.4`) |

---

## D. WITHDRAWAL / LOCK RULES

### D.1 `is_withdrawal_available` — the exact condition

`db:is_withdrawal_available(position_id uuid) RETURNS boolean`:

```sql
SELECT lock_end_date, btc_wallet_locked, withdrawal_executed
INTO   lock_end, wallet_locked, withdrawal_done
FROM   founder_positions WHERE id = position_id;

RETURN ( lock_end IS NOT NULL
     AND now() >= lock_end
     AND wallet_locked = true
     AND withdrawal_done = false );
```

**This function is about `founder_positions` only. It has nothing to do with staking pools.** There
is no equivalent function for staking withdrawals — the staking lock check exists only in the
browser (§D.3).

Note the third clause: withdrawal requires `btc_wallet_locked = true`. A founder whose wallet is
*not* locked can never withdraw, and nothing sets that flag on the happy path.

### D.2 Founder position lock

| Rule | Value | Citation | Enforced? |
|---|---|---|---|
| Lock period | 90 days from deposit | `db:create_prime_founder_position` (`withdrawal_available_date = now() + INTERVAL '90 days'`); `v2:pages/FounderPool.tsx:356` | Only via `is_withdrawal_available`, which has **no caller in any edge function or migration** |
| Minimum deposit | ≥ $10,000 | `db:founder_positions_min_deposit_check`, `db:founder_position_min_deposit_check` | **YES** — CHECK constraint |
| Maximum position | `max_usd_limit ≤ 1,000,000` and `current_usd_value ≤ max_usd_limit` | `db:founder_positions_max_usd_check`, `db:founder_positions_current_value_check` | **YES** — CHECK constraints |
| Founder currency | `btc` or `ethereum` only | `db:founder_position_currency_check` | **YES** |
| USD sanity band | `0 < current_usd_value ≤ 10,000,000` | `db:validate_founder_position_input` trigger | **YES** |
| Position types | `standard` \| `prime` | `db:founder_position_type_check` | **YES** |

### D.3 Staking lock — client-side only

| Rule | Value | Citation |
|---|---|---|
| `lock_end_date` set on stake | `now() + duration_months months` | `db:distribute_enhanced_rewards`; `db:process_staking_request` |
| Rewards stop at lock end | filter `lock_end_date IS NULL OR > NOW()` | `mig:20251130074027:40` — present in the **DB** function |
| Rewards stop at lock end (edge) | **absent** | `fn:manual-rewards-distribution/index.ts:188-190` filters only `status='active'` |
| Withdrawal minimum period | 90 days global; per-token str 90 / ccos 120 / wstr 180 / btc 365 / eth 270 / bnb 90 / domain 90 | `v2:pages/StakingWithdrawals.tsx:61,64-72` — **browser only** |
| Unlock test | `now >= created_at + stakingPeriodDays × 86400000` | `v2:pages/StakingWithdrawals.tsx:182-185` — **browser only** |
| **The withdrawal itself** | `// Here you would implement the actual withdrawal logic` — a toast fires and nothing is persisted | `v2:pages/StakingWithdrawals.tsx:254-255` |
| Withdrawal addresses | held in React state, never written to the DB | `v2:pages/StakingWithdrawals.tsx:232-235` |
| Reward eligibility delay | 24 hours after pool creation | `db:distribute_vested_rewards` (`created_at < NOW() − INTERVAL '1 day'`); UI at `v2:components/StakingPoolEligibilityBadge.tsx:19,38-39` |

### D.4 Early exit / penalties

| Rule | Value | Citation | Enforced? |
|---|---|---|---|
| Emergency-unstake penalty | duration halved (`Math.floor(duration/2)`), rewards recomputed at the reduced APY, penalty = difference | `v2:components/StakingCalculator.tsx:54-59,70`; UI copy "50% duration penalty" `v2:pages/Staking.tsx:510` | **Display only.** No DB function, migration, or edge function implements any penalty |
| Unstake path | `db:process_staking_request` `request_type='unstake'` | see §I-7 — subtracts from **every** matching pool, credits nothing back, ignores `lock_end_date` entirely | Broken |
| Pre-CEX STR voucher lock | balance, staked_amount, status, pool_type and APY all immutable, and DELETE blocked, while `lock_end_date > now()`; lock end cannot be shortened; APY must stay 0 | `db:enforce_precex_str_voucher_lock` via trigger `trg_enforce_precex_str_voucher_lock` | **YES** — the single strongest lock in the system, and the only one implemented as a trigger |

### D.5 Withdrawal request lifecycle

| Table | Statuses | Where set | Enforced? |
|---|---|---|---|
| `withdrawal_requests` | default `'pending'`; UI renders `'completed'` | `db:withdrawal_requests`; `v2:components/…/WithdrawalInterface.tsx:92,255-256` | **No CHECK constraint** on `status`. `audit:§6.2 H6`: the RLS policy at `mig:20250722195629:38-41` lets a user **self-approve and redirect their own withdrawal** |
| `guardian_withdrawal_requests` | `pending, processing, approved, completed, rejected, cancelled` | `db:guardian_withdrawal_requests_status_check` | **YES** — CHECK |
| `staking_requests` | `pending → approved \| rejected`, admin-only via `db:process_staking_request` (`IF NOT is_admin(auth.uid()) THEN RAISE`) | `db:process_staking_request` | Function-level admin check: **YES**. No CHECK on the column |

---

## E. MINTING / ISSUANCE RULES

Every path below **creates value with no corresponding debit anywhere** unless the "Debits?" column
says otherwise.

| # | Path | Formula | Debits? | Citation |
|---|---|---|---|---|
| **E-1** | `calculate_ccos_mint(pool_amount, pool_type, current_price)` | `usd_value = pool_amount × current_price`; `mint_pct = 12.5 + random() × 5.0`; `ccos = usd_value × mint_pct / 100` (comment: "assuming 1 CCOS = $1") | **No** — pure function, returns an amount | `db:calculate_ccos_mint` |
| **E-2** | `distribute_enhanced_rewards(user, token_type, amount, duration, efficiency)` | Inserts or increments a `user_staking_pools` row with `balance = staked_amount = original_stake_amount = amount`, `apy_rate = dynamic_apy = calculate_dynamic_apy(...)`, `lock_end_date = now() + duration months` | **No.** No balance check, no source lookup, no pool lookup, no min-stake check, and `EXECUTE` left at the `PUBLIC` default — no migration in the V1 history revokes it (`audit:§7.3` records the revocation script as staged-but-unapplied; the first real `REVOKE` is the 2026-08-18 forward-fix). **Any authenticated session — and `anon` — could call it with any `user_id` and any amount** | `db:distribute_enhanced_rewards` (latest def `mig:20250929031813:51-161`) |
| **E-3** | Internal-wallet CCOS stake | `fn:submit-staking-request` *reads* the CCOS pool balance to verify sufficiency (`:123-149`) and then never debits it; `db:process_staking_request` inserts a new pool with `balance = staked_amount = amount` | **No** — source pool untouched | `fn:submit-staking-request/index.ts:123-149`; `db:process_staking_request` |
| **E-4** | `credit_voucher_tokens(user, token_type, package)` | Pre-CEX STR: fixed table (166,666 STR for $250 … 66,666,666 STR for $100,000 ≈ **$0.0015/STR**). Legacy: fixed table, else `token_amount = ROUND(usd_amount / price_per_token, 2)` with `ccos → 9.0`, `str → 0.00911`, `arss → 0.00911` | **No** — voucher-backed by design, but nothing verifies payment; called by trigger `auto_credit_voucher_trigger` on `voucher_redemptions` | `db:credit_voucher_tokens` |
| **E-5** | Signup ARSS welcome bonus | 1,000.00 ARSS into `user_wallets.arss_balance` | **No** | `db:create_user_wallet`; `db:handle_new_user_signup` |
| **E-6** | STARW node reward | 2.9 wSTR/node/day into `starw_wstr_rewards` | **No** | `mig:20260322052154:59` |
| **E-7** | Supernode reward | 27.7 wSTR/node/day into `supernode_wstr_rewards` | **No** | `mig:20260322053054:66` |
| **E-8** | Staking rewards | §C.2 — `staked × APY/100/365` into two spendable stores at once | **No** | `mig:20251130074027` |
| **E-9** | `backfill_historical_rewards` | `rewards_earned = expected_total` (assignment) + `balance += missing` | **No** | `mig:20251130074246:58-64` |
| **E-10** | `auto_mint_profile_domain` | Mints a `str_domains` row (`status='minted'`) from `user_profiles.str_domain_username` when 3–63 chars and not a placeholder | **No** — free | `db:auto_mint_profile_domain` |
| **E-11** | Supernode fiat credit | Hardcoded `INSERT INTO fiat_wallets` crediting three named user UUIDs $100,000 / $50,000 / $50,000 as `held_balance` | **No** | `mig:20260322053054:6-14` |
| **E-12** | `transfer_staking_pool_atomic` | `SET balance = balance − amount` on the sender (locked, `balance >= amount`), `balance + amount` on the receiver | **YES** — genuinely atomic and balanced | `db:transfer_staking_pool_atomic` |
| **E-13** | `debit_staking_pool_balance` | `SET balance = balance − amount` on the highest-balance qualifying pool, `FOR UPDATE` | **YES** — debit only | `db:debit_staking_pool_balance` |
| **E-14** | `convert_wstr_to_fiat_atomic` | Locks the user's `arss_transactions`, recomputes the wSTR balance, inserts a `debit` row, credits `fiat_wallets` | **YES** — balanced | `db:convert_wstr_to_fiat_atomic` |

**`calculate_ccos_mint` uses `random()`.** Two identical deposits mint different amounts of CCOS,
somewhere in a 12.5%–17.5% band — a 40% spread on the issued quantity. The DB CHECK
`guardian_margin_settings_margin_percent_check (margin_percent BETWEEN 12.5 AND 17.5)` shows the
band was a deliberate parameter; making it random rather than configured is not.

---

## F. TIER / STATUS RULES

### F.1 The two independent status axes

| Enum | Values | Column | Meaning |
|---|---|---|---|
| `user_status` | `standard, silver, gold, platinum, vip` | `user_profiles.user_status`, default `'standard'` | Cosmetic badge |
| `account_status` | `pending, approved, suspended, closed` | `user_profiles.status` | Operational; `'approved'` gates `db:calculate_daily_rewards` |
| `app_role` | `admin, moderator, user, support, marketing, legal, arx, seed_str_admin` | `user_roles.role` | Authorization |

Sources: `db:pg_enum`; `mig:20250801144619_e6b35b3c…:15,20`; `mig:20250720000000_recovered_dashboard_objects.sql:33`.

### F.2 What moves a user between tiers

**Nothing automatic.** There is no threshold function, no trigger, and no scheduled job that reads a
balance and assigns a `user_status`. The only writer is:

```
update_user_badge_status(target_user_id uuid, new_user_status user_status)
  → UPDATE user_profiles SET user_status = new_user_status
```
— `mig:20250801144619_e6b35b3c…:96,110` (identical copy at `mig:20250801144725:70,84`).

In the frontend it is four literal buttons with no condition attached:
`v2:components/…/EnhancedUserManagement.tsx:541` (silver), `:548` (gold), `:555` (platinum), `:562` (vip).

Two triggers make `user_status` admin-only:
`RAISE EXCEPTION 'Not allowed to modify user_status'` (`mig:20260616073505:62-63`) and
`'user_status can only be changed by an administrator.'` (`mig:20260706080259:51-52`); a third
freezes it on profile self-update (`mig:20260615145735:43`).

### F.3 What each tier grants

**Nothing.** Exhaustive grep across `v1:src/`, `v2:src/`, all 696 migrations and all edge functions
finds `user_status` used only for badge text and badge colour:
`v2:components/…/EnhancedUserManagement.tsx:193-201`, `v2:pages/AdminDashboard.tsx:411-415,808-830`,
`v2:components/…/UserAccountOverview.tsx:152-158`. No fee, APY, limit, or feature reads it.

### F.4 The one tier system that *does* have thresholds: VIP

`db:update_vip_status` (`mig:20251001053701_2f45fabf…:32-125`) — a separate table (`vip_users`),
unrelated to the `user_status` enum:

| Qualification | Threshold | `qualification_type` |
|---|---|---|
| STR staked | `SUM(staked_amount WHERE pool_type='str') >= 10,000,000` | `str_holder` |
| Domains staked | `SUM(staked_amount WHERE pool_type='domain') >= 1,000` | `domain_holder` |
| Both | both thresholds met | `both` |
| Demotion | fails both → `vip_status = 'inactive'` (`:107-115`) | |

It sums **`staked_amount` across every pool including unbacked ones**, and it has **no cron
schedule and no caller** — `update_vip_status` appears in no edge function and no frontend file.
It has never run on a schedule.

### F.5 Other tier-shaped things (marketing only, no enforcement)

| Tier set | Thresholds | Citation |
|---|---|---|
| Domain pool tiers | Personal 100 STR / Business 500 / Premium 2,500 / Brands 10,000 | `v2:components/PoolDeploymentSection.tsx:115,127,139,151` |
| CCOS package tiers | $5k/$10k = 5% bonus, $20k/$30k = 10%, $50k = 20%; ARX access at ≥$20,000 | `v2:pages/CcosSale.tsx:14-18` |
| SAFE share bonus tiers | 2,500 sh = +2.5%, 5,000 = +5%, 10,000 = +10%, 25,000 = +12.5% | `v1:pages/SsiPrivateSharesSale.tsx:48-52` |
| Domain type enum | `standard, premium, business, brand` — but `standard, premium, enterprise` elsewhere | `v2:components/marketplace/CreateListingDialog.tsx:93-94` vs `v2:…/SourceLessIntegration.tsx:13` |

---

## G. FEES / PRICING

### G.1 Fees

| Fee | Rate | Where computed | Server-side? |
|---|---|---|---|
| **CCoin Bank rail fee** (in CCOS) | sepa 0.5 · swift 2.0 · wire 2.0 · uk_payment 0.5 · internal/network/account/email 0.1 · card_topup 0.2 · swap_fiat 0.3 · swap_crypto 1.0 | `c:/tmp/ignitehex-v2/supabase/functions/ccoin-bank-ccos-fee/index.ts:9-21` | **YES** — the only properly server-side fee in the system |
| CCoin Bank auto-swap rates (to cover a CCOS fee shortfall) | STR 1000 · wSTR 885 · EUR 9.35 · USD 10.13 · CHF 8.9 · GBP 7.95 per CCOS | `…/ccoin-bank-ccos-fee/index.ts:25-32` | Server-side, but **hardcoded constants, no oracle** |
| Card top-up fee (client default) | `data.fee?.fee_ccos ?? 0.2` | `v2:components/ccoin-bank/CardTopUpDialog.tsx:63` | Falls back client-side |
| **Currency exchange fee** | 0.25% | `v1:pages/FinancialPlatform.tsx:251` and `v1:pages/IbanManagement.tsx:748-749` | **NO** — computed in the browser and inserted straight into `currency_exchanges` with `status:'completed'` |
| **Token sell fee** | 2% (`feeRate = 0.02`) | `v1:pages/SellTokens.tsx:120-123` | **NO** — client-side (path is currently a stub) |
| Domain marketplace commission | **0%** ("Zero Fees", "0% commission!") | `v1:components/marketplace/DomainMarketplaceListings.tsx:353,460` | n/a. The column `domain_marketplace_transactions.transaction_fee` exists and is never populated |
| Affiliate / referral commission | **No rate exists anywhere.** `seed_str_referrals.commission_amount` defaults `0`; `referrals.reward_amount` defaults `0` | `db:seed_str_referrals`, `db:referrals` | No rate, no calculator, no trigger. `audit:§4.5`: `referrals` has 0 rows |
| CCoin Bank "CCOS holder" tier | 0.00% on payments & transfers | `v1:pages/CCoinBankPro.tsx:467,553` | Marketing copy; no code reads a CCOS balance to waive a fee |
| Founder gas fee (statement text) | 0.0001 CCOS | `v2:pages/FounderPool.tsx:552` | Display only |

### G.2 Prices — and where each is computed

| Asset | Price | Computed where | Client-side? |
|---|---|---|---|
| **STR (live)** | `0.028 + Math.random() × (0.0318 − 0.028)`, 5 dp — a **fresh random number on every request** | `fn:str-price/index.ts:15-19` | Server-side function, but non-deterministic. Drives the live wSTR→fiat cashout at `fn:convert-wstr-to-fiat/index.ts:46,56,82` |
| STR (v2 client fallback) | same `Math.random()` expression | `v2:lib/hardenedStr.ts:4-7` | **YES** |
| STR (v1 working tree) | `STR_FALLBACK_PRICE = 0.0299`, deterministic, with `isFallbackPrice()` | `v1:lib/hardenedStr.ts:22,29,37` | Client, but fixed — **this fix is in the working tree only and the edge function is still random** |
| **wSTR** | `STR × 1.13` (13% "wrapper premium") | `v2:lib/priceUtils.ts:117` | **YES** |
| **CCOS** | `STR × 1000` | `v2:lib/priceUtils.ts:118` | **YES** |
| CCOS (voucher) | `9.0` | `db:credit_voucher_tokens` | Server |
| CCOS (package constant) | `10.13` | `v2:lib/packageOptions.ts:67` | **YES** — and `audit:§3.8` puts the 9.0-vs-10.13 gap at ≈114M CCOS over-credited |
| CCOS (founder fallback) | `38.729`, and silently `1` at `v2:pages/FounderPool.tsx:430` | `v2:pages/FounderPool.tsx:743,430` | **YES** |
| CCOS (ecosystem valuation) | `0.0021` | `db:get_total_ecosystem_value` | Server |
| CCOS (mint assumption) | `$1` ("assuming 1 CCOS = $1 for simplicity") | `db:calculate_ccos_mint` | Server |
| **ARSS** | `STR × 1.13 × 0.13` | `v2:lib/priceUtils.ts:119` | **YES** |
| ARSS (sale) | `ARSS_PRICE = 0.0035` | `v1:pages/ArssTokenPurchase.tsx:27` | **YES** |
| ARSS (voucher) | `0.00911` | `db:credit_voucher_tokens` | Server |
| ARSS (sell fallback) | `0.15` | `v1:pages/SellTokens.tsx:103` | **YES** |
| **STR (voucher, legacy)** | `0.00911` | `db:credit_voucher_tokens` | Server |
| STR (voucher, Pre-CEX) | `0.0015` implied by the fixed table ($250 → 166,666 STR) | `db:credit_voucher_tokens` | Server |
| STR (ecosystem valuation) | `1.85` | `db:get_total_ecosystem_value` | Server |
| STR (seed) | `investment_amount × 0.0015` | `v2:pages/SeedStrBuy.tsx:264` | **YES** |
| STR (pool deployment) | `0.024689789805739916` | `v2:components/PoolDeploymentSection.tsx:286` | **YES** — hardcoded |
| eSTR | `STR × 1.2` | `v2:lib/priceUtils.ts:120` | **YES** |
| STR$ / str_stable | `1` | `v2:lib/priceUtils.ts:121-122` | Hardcoded peg |
| **STARW node** | `NODE_PRICE = 13000` ($13,000) | `v1:pages/StarwSale.tsx:15`, `v2` same | **YES** |
| **Supernode** | `39000` ($39,000) | `v1:pages/StarwSale.tsx:78,955` | **YES** |
| **SAFE share** | `PRICE_PER_SHARE_USD = 20` | `v1:pages/SsiPrivateSharesSale.tsx:29` | **YES** |
| Private digital share | `9.00` (column default) | `db:private_digital_shares_purchases.price_per_share` | Server default |
| BTC | `113000` (v2 lib) / `95000` (ARSS page) / `70000` (withdrawal) / `119000` (founder) | `v2:lib/priceUtils.ts:128`; `v1:pages/ArssTokenPurchase.tsx:52`; `v2:…/WithdrawalInterface.tsx:81`; `v2:pages/FounderPool.tsx:745` | **YES** — four different hardcoded BTC prices |
| ETH | `3500` / `3700` / `3200` | `v2:lib/priceUtils.ts:129`; `v2:pages/FounderPool.tsx:746`; `v2:pages/StakingWithdrawals.tsx:81` | **YES** |
| FX (wSTR conversion) | `forex-rates` edge fn; falls back to EUR 0.92 / GBP 0.79 / CHF 0.88 | `fn:convert-wstr-to-fiat/index.ts:70-75` | Server, with hardcoded fallback |
| FX (dead DB fn) | EUR 0.92 / GBP 0.79 / CHF 0.88 / USD 1.0, on a **1 wSTR = 1 USD** assumption | `mig:20251101122302:26-32` (`convert_wstr_to_fiat`) | Server; **zero callers** — `audit:§7.4` |
| FX (bank UI) | EUR→USD 1.09, USD→EUR 0.92, GBP→EUR 1.175, else 1.0 | `v1:pages/FinancialPlatform.tsx:246-248` | **YES** |
| Exchange "market spread" | `basePrice × (0.98 + Math.random() × 0.04)` etc., presented as CoinPaprika / LiveCoinWatch / CoinGecko quotes | `v2:lib/priceUtils.ts:131,139,147` | **YES — fabricated** |

### G.3 Bonuses

| Bonus | Rate | Citation | Server-side? |
|---|---|---|---|
| ARSS purchase | `BONUS_PERCENT = 50` (+50% tokens) | `v1:pages/ArssTokenPurchase.tsx:28`, applied `:62`, written to DB `:187-188` | **NO** |
| STARW node ARSS grant | 1,000 ARSS per node | `v2:pages/StarwSale.tsx:858` | **NO** |
| Domain staking wSTR bonus | 1,000 wSTR per staked domain | `v2:pages/StakingWithdrawals.tsx:291-292`; `v2:components/PoolDeploymentSection.tsx:315` | **NO** |
| CCOS package bonus | 5% / 10% / 20% by tier | `v2:pages/CcosSale.tsx:14-18` | **NO** |
| SAFE share bonus | 2.5 / 5 / 10 / 12.5% by volume | `v1:pages/SsiPrivateSharesSale.tsx:48-52`, written `:228-230` | **NO** |
| Founder expected return | `usdValue × 1.5` (+50%) written to `founder_positions.expected_btc_return` | `v2:pages/FounderPool.tsx:369`; DB precedent `db:create_prime_founder_position` (350,000 → 525,000) | **NO** |
| Signup ARSS | 1,000 ARSS | `db:create_user_wallet` | **YES** |

### G.4 Prices and amounts computed CLIENT-SIDE and written straight to the database

Every row is a monetary value calculated in the browser and persisted with no server recomputation.
This is the single largest class of unenforced rule in the platform.

| # | Value(s) | Destination | Citation |
|---|---|---|---|
| 1 | `arss_amount`, `bonus_amount` (50%), `total_arss_amount`, `arss_price_at_purchase`, `crypto_price_at_purchase`, `usd_amount`, `crypto_amount` | `arss_token_purchases` insert | `v2:pages/ArssTokenPurchase.tsx:61-66`, insert `:177-197` |
| 2 | `total_cost`, `btc_amount`, `eth_amount`, `crypto_prices_at_purchase`, `arss_bonus` | `starw_purchases` insert | `v2:pages/StarwSale.tsx:77,836-842`, insert `:845-861` |
| 3 | `total_cost = count × 39000`, btc/eth amounts | `supernode_purchases` insert | `v2:pages/StarwSale.tsx:78,1902-1908`, insert `:1910-1926` |
| 4 | `package_amount_usd` (client-chosen) | `ccos_purchases` insert | `v2:pages/CcosSale.tsx:173-183` |
| 5 | `payment_amount`, `payment_usd` (= `investment × 0.0015 ÷ live crypto price`) | `seed_str_applications` update | `v2:pages/SeedStrBuy.tsx:262-278`, update `:321-338` |
| 6 | `expected_btc_return = usd × 1.5`, `max_usd_limit`, `min_deposit_usd`, `current_usd_value` | `founder_positions` insert | `v2:pages/FounderPool.tsx:358-372` |
| 7 | `amount`, `ccos_minted`, `mint_percentage`, `usd_value_at_time`, **a fabricated `transaction_hash` = `0x${Math.random().toString(16)}`**, and `status:'completed'` | `founder_pool_transactions` insert | `v2:pages/FounderPool.tsx:341-343,388-389,406`, insert `:407-421` |
| 8 | `balance`, `usd_value` recomputed and overwritten by the browser | `founder_pools` update | `v2:pages/FounderPool.tsx:394-402,426-432` |
| 9 | `last_price`, `usd_value` overwritten in a loop from client-fetched prices | `founder_pools` update | `v2:pages/FounderPool.tsx:250-256` |
| 10 | `usd_value_at_request = amount × 70000` (hardcoded BTC price), `btc_amount` | `withdrawal_requests` insert | `v2:…/WithdrawalInterface.tsx:81-93` |
| 11 | `to_amount`, `exchange_rate`, `fee_amount` (0.25%), `status:'completed'` | `currency_exchanges` insert | `v1:pages/FinancialPlatform.tsx:246-265`; `v1:pages/IbanManagement.tsx:748-764` |
| 12 | `shares`, `bonus_pct`, `bonus_shares`, `total_shares`, `price_per_share_usd` | `safe_purchases` insert | `v1:pages/SsiPrivateSharesSale.tsx:227-231` |

Rows 7 and 11 write `status:'completed'` from the browser — a user with the network tab open can
mint a completed, fee-free, arbitrarily-priced transaction. Row 7 additionally fabricates the proof
of payment.

The one path done correctly: staking goes through a server-validated edge function
(`v2:components/StakingForm.tsx:241-256` → `fn:submit-staking-request`, Zod schema at `:11-44`).

---

## H. CAPS AND INVARIANTS

Legend: **ENFORCED** = a DB constraint, trigger, or a server-side function that actually runs on the
live path. **PARTIAL** = enforced on one path but bypassable via another. **ASSUMED** = stated in UI,
docs or a comment, with nothing in the DB or on the server enforcing it.

### H.1 Supply caps

| Invariant | Status | Evidence |
|---|---|---|
| `Σ CCOS ≤ 63,000,000` | **ASSUMED** | Owner ground truth `audit:§2`. Grep for `63000000` / `max_supply` / `total_supply` across all 696 migrations **and** all edge functions returns **zero hits**. Live breach 16.3× (`audit:§3.1`) |
| `Σ STR ≤ 63,000,000,000` | **ASSUMED** | Same. Live 27.5B = 44% of cap (`audit:§9.1`) — but 14.1B of that is enhanced-pool phantom (`audit:§3.2`) |
| ARSS / DOMAIN / eSTR / wSTR supply | **NOT DEFINED** | No cap exists to enforce |
| `enhanced_staking_pools.tvl_cap` | **ASSUMED (dead)** | Column exists (`mig:20250720000000:668`); grep across migrations, functions and `src/` finds no read and no write |
| STARW nodes ≤ 100 | **ENFORCED** | `db:starw_nodes_node_number_check (node_number BETWEEN 1 AND 100)`. UI advertises 39 (`v1:pages/StarwSale.tsx:16`) — the two disagree |
| Supernodes ≤ 1,000 | **ENFORCED** | `db:supernodes_node_number_check` |

### H.2 Non-negative money

| Invariant | Status | Evidence |
|---|---|---|
| `user_staking_pools.balance >= 0` and `staked_amount >= 0` | **ENFORCED** | `db:validate_staking_balance` on trigger `validate_staking_balance_trigger`; also caps `balance ≤ 999,999,999,999,999` |
| `wallet_transactions.amount > 0` | **ENFORCED** | `db:validate_transaction_amount` on trigger `validate_transaction_amount_trigger` |
| `ccoin_internal_iban_currencies.balance >= 0` | **ENFORCED** | CHECK constraint |
| `ccoin_network_transactions.amount > 0`, `pos_transactions.amount > 0` | **ENFORCED** | CHECK constraints |
| `fiat_wallets.balance / available_balance / held_balance >= 0` | **ASSUMED** | `mig:20251025052024:6-8,40-42` **declares** `NUMERIC NOT NULL DEFAULT 0 CHECK (… >= 0)` — but it declares it inside a `CREATE TABLE IF NOT EXISTS`, and `fiat_wallets` already existed from `mig:20250720000000`. The statement is a no-op. `pg_constraint` on `fiat_wallets` holds only the PK and `UNIQUE(user_id, currency)` — **the CHECKs do not exist** |
| `user_wallets.arss_balance >= 0` | **ASSUMED** | No CHECK, no trigger |
| `crypto_wallets.balance >= 0` | **ASSUMED** | No CHECK, no trigger. `mig:20251026091755:27` declares `CHECK (balance >= 0)` under the same ineffective `IF NOT EXISTS` pattern |
| `arss_transactions.amount > 0` | **ASSUMED** | No CHECK. Sign is carried by `transaction_type`, so a negative `amount` on a `credit` row silently debits |
| `fiat_wallets: available + held == balance` | **ASSUMED, and known broken** | `held_balance` is assigned (not incremented) and **never decremented anywhere** — `audit:§5.1 B1`, $1,056,727 permanently frozen |

### H.3 Ledger integrity

| Invariant | Status | Evidence |
|---|---|---|
| `Σ arss_transactions == spendable wSTR` | **ENFORCED for reads** | `db:get_user_wstr_balance` is the definition — but only for six of the ~15 `transaction_type` values in use (§C.4) |
| Every balance mutation has a matching ledger row | **ASSUMED** | `process-swap` credits with no ledger row (`audit:§5.2 B4`); `debit_staking_pool_balance` and `transfer_staking_pool_atomic` write no ledger row either |
| Staking rewards are credited once per pool per day | **PARTIAL** | `db:distribute_vested_rewards` selects on `last_reward_date < today` but the `UPDATE … WHERE id = pool_record.id` carries **no date guard**, so concurrent invocations double-credit (`audit:§5.1 R1`, root of the 2.49B wSTR over-issue) |
| STARW / supernode rewards once per node per day | **ENFORCED** | `UNIQUE(starw_node_id, reward_date)` / `UNIQUE(supernode_id, reward_date)` plus a `NOT EXISTS` guard — the two best-built reward paths in the system |
| Airdrop credited once per user | **ASSUMED** | No `UNIQUE(user_id)`; credited per-registration (`audit:§5.2 R5`) |
| One pool per (user, pool_type, duration) | **NOT ENFORCED** | `mig:20251205142711:3-4` **drops both** `user_staking_pools_unique_duration` and `user_staking_pools_user_id_pool_type_stake_duration_months_key`. `pg_constraint` confirms the only remaining unique on the table is `PRIMARY KEY (id)`. Unlimited duplicate pools are now legal — see §I-26 |
| Staked tokens are backed by a payment | **ASSUMED** | 113 users hold 1,902,904,977 staked tokens with no voucher, crypto order, or approved request (`audit:§3.2`) |

### H.4 Access and lock invariants

| Invariant | Status | Evidence |
|---|---|---|
| Only admins process staking requests | **PARTIAL** | The `(uuid, boolean, text)` overload checks `IF NOT is_admin(auth.uid()) THEN RAISE EXCEPTION`. The `(uuid, text, text)` overload — last written by `mig:20251218042835` — has **no authorization check at all** (§I-8) |
| Only admins change `user_status` | **ENFORCED** | Triggers at `mig:20260616073505:62-63`, `mig:20260706080259:51-52` |
| Users cannot write their own staking pools | **ENFORCED (production)** | `mig:20260509121934:11-13` drops the self-write policies. **Not true in the local rebuild** — see the caveat at the top |
| Users cannot insert `arss_transactions` / `ccoin_ledger` | **ENFORCED (production)** | `mig:20260509121934:3-8` |
| `distribute_enhanced_rewards` restricted to admins | **NOT ENFORCED in V1** | `EXECUTE` defaulted to `PUBLIC` throughout the V1 history — no migration up to `mig:20260706…` revokes it, and `audit:§7.3` records the revocation script as staged but unapplied. Closed only by the 2026-08-18 forward-fix in the v2 tree |
| `debit_fiat_wallet` / `debit_staking_pool_balance` verify the caller owns `p_user_id` | **NOT ENFORCED in V1** | Both are `SECURITY DEFINER`, take `p_user_id` as a parameter, and were granted to `anon` and `authenticated` with no ownership test — any session could debit any account. Closed only by the 2026-08-18 forward-fix |
| Pre-CEX voucher pools immutable while vesting | **ENFORCED** | `db:enforce_precex_str_voucher_lock` trigger |
| Staking lock prevents withdrawal | **ASSUMED** | Browser-only (`v2:pages/StakingWithdrawals.tsx:182-185`); the withdrawal handler is a stub (`:254-255`) |
| Founder lock prevents withdrawal | **PARTIAL** | `db:is_withdrawal_available` implements it correctly and **has no caller** |
| Users cannot self-approve withdrawals | **NOT ENFORCED** | `audit:§6.2 H6` — RLS at `mig:20250722195629:38-41` |
| Users cannot self-approve vouchers | **NOT ENFORCED** | `audit:§6.3 M6` |

### H.5 Range invariants that *are* enforced

| Invariant | Constraint |
|---|---|
| Founder min deposit ≥ $10,000 | `founder_positions_min_deposit_check`, `founder_position_min_deposit_check` |
| Founder `max_usd_limit ≤ $1,000,000` | `founder_positions_max_usd_check` |
| Founder `current_usd_value ≤ max_usd_limit` | `founder_positions_current_value_check` |
| Founder position currency ∈ {btc, ethereum} | `founder_position_currency_check` |
| ARSS purchase `usd_amount` ∈ [100, 100,000] | `arss_token_purchases_usd_amount_check` |
| Guardian margin ∈ [12.5, 17.5] | `guardian_margin_settings_margin_percent_check` |
| Staking duration ∈ {3,6,9,12,24,36,48} | `staking_requests_duration_check` |
| Pool type ∈ 7 values | `user_staking_pools_pool_type_check` |
| Domain name 3–63 chars, unique | `str_domains_domain_name_format` + `check_domain_uniqueness` trigger |
| CCoin IBAN / card / magnet-address format | `internal_iban_format`, `card_number_format`, `magnet_address_format` regexes |

---

## I. CONTRADICTIONS AND UNENFORCED INVARIANTS

This is the section that matters. Each entry names the sources that disagree and what the
disagreement costs.

### I-1. Fifteen APY tables, no reconciliation — **CRITICAL**

Nine server-side (§B.3) and six client-side (§B.4). For **STR, 12 months**, the platform
simultaneously holds:

| Value | Source |
|---|---|
| 30% | `v2:pages/SuperAdminDash.tsx:61` (admin console) |
| 22% | `db:calculate_dynamic_apy` (what an enhanced stake is actually assigned) |
| 20% | `db:update_pool_apy_by_duration` (what the sweeper writes) |
| 20% | `mig:20251218042415:6-15` (the one-off domain UPDATE, for domain) |
| 18–22% | `enhanced_staking_pools` `STR Momentum Lock`; `v2:components/StakingForm.tsx:140` (what the user is quoted) |
| 15% | `mig:20250929154826:147` duration-only table; `v2:components/PoolSplittingManager.tsx:77` |
| 12.5% | `mig:20251207055432:32-67` |
| 20% *as a fraction* → the same number arrived at through incompatible units | `db:calculate_staking_rewards` (`0.20`, no `/100`) |

For **STR, 48 months**: 60% (`SuperAdminDash.tsx:63`) vs 70% (`update_pool_apy_by_duration`) vs 66%
(`calculate_dynamic_apy`) vs 65–75% (`enhanced_staking_pools`) vs 25% (duration-only table,
`PoolSplittingManager.tsx:77`) vs **20%** (`mig:20251207055432`).

For **DOMAIN, 48 months**: 82.5% (`update_pool_apy_by_duration`) vs 80% (`enhanced_staking_pools`)
vs **35%** (`mig:20251218042415`, written directly onto rows) vs **16%** (`mig:20251207055432`).

For **STR, 36 months**: `SuperAdminDash` has no entry and reports **0%**
(`v2:pages/SuperAdminDash.tsx:82` `|| 0`) against an actual 46%.

Which rate a given pool carries depends entirely on **which code path last touched it, and on what
date** — voucher credit (13), enhanced stake (`calculate_dynamic_apy`), the admin sweeper
(`update_pool_apy_by_duration`), the 2025-10-01 migration that set `apy_rate = apr_max`, the
2025-12-07 low table, the 2025-12-18 domain UPDATE, or the 2026-01 backfills. There is no
reconciliation job and no assertion. Two users who staked the same token for the same duration on
different days are on different schedules, permanently.

The **DOMAIN ladder is also non-monotonic in the seed itself**: `mig:20251001053005:12-17` sets
DOMAIN 6m = 18.5, **9m = 13.0** (below 6m), 12m = 25.0, 24m = 39.0, **36m = 22.0** (below 12m),
48m = 80.0. Locking longer pays less at two points on the curve.

### I-2. Three definitions of "wSTR balance" — **CRITICAL**

| Definition | Source | Used by |
|---|---|---|
| `Σ arss_transactions` over six transaction types | `db:get_user_wstr_balance` | the fiat cashout |
| `user_staking_pools.balance` | the pools themselves | `db:debit_staking_pool_balance`, transfers |
| `Σ user_staking_pools.rewards_earned` | dashboard | display |

Every reward is written into **both** of the first two (`mig:20251130074027:59-60` and `:66-88`), so
the same reward is spendable twice — once by converting to fiat, once by transferring the pool
balance. `audit:§3.3` measures the resulting divergence at **54×**: 2,672,697,219 wSTR in the ledger
against 49.2M of `rewards_earned` in the pools.

### I-3. Every correction transaction type is invisible — **CRITICAL**

`db:get_user_wstr_balance` sums only `credit, staking_reward, airdrop, purchase, manual_credit,
voucher_credit` (+) and `debit, withdrawal, transfer_out` (−). The correction types written by every
`fix_*` and `correct_*` path (`balance_correction`, `admin_correction`, `voucher_correction`,
`migration_correction`, `staking_reward_correction`) are all in the `ELSE 0` branch. **−9,396,884,459
wSTR of intended clawbacks have zero effect** (`audit:§3.4`). Also invisible: `earn` (written by
`db:calculate_daily_rewards`) and `voucher_redemption` (written by `db:credit_voucher_tokens`) — so
voucher tokens never reach the wSTR balance at all.

### I-4. The enhanced-stake path mints tokens from nothing, and anyone can call it — **CRITICAL**

`db:distribute_enhanced_rewards` inserts `balance = staked_amount = original_stake_amount = amount`
with:
- no balance check,
- no debit of any source,
- no pool lookup (the 2025-09-03 version at `mig:20250903045926:42-60` looked up
  `enhanced_staking_pools` and enforced `min_stake_amount`; the live 2025-09-29 version
  `mig:20250929031813` **removed both**),
- `EXECUTE` defaulting to `PUBLIC`.

Live result: 15.6B tokens staked across 546 enhanced pools, including a single account holding
**8.1B STR + 1B CCOS + 500M domain** (`audit:§3.2`). The 1B CCOS alone is **16× the entire declared
CCOS supply cap.** These phantom stakes then accrue real, cashable wSTR daily.

### I-5. Supply caps exist only as prose

`CCOS ≤ 63,000,000` and `STR ≤ 63,000,000,000` are owner-stated ground truth (`audit:§2`) and appear
in the UI (`v1:pages/CCoinBankPro.tsx:618,621`). They appear in **no CHECK constraint, no trigger, no
function, and no edge function** — grep for `63000000`, `max_supply`, `total_supply` across all 696
migrations and all 90 edge functions returns nothing. Nothing can detect a breach, let alone prevent
one. CCOS is currently **16.3× over** (`audit:§3.1`).

The `tvl_cap` column on `enhanced_staking_pools` is the one place a cap was designed in. It is never
read or written by anything.

### I-6. `calculate_ccos_mint` issues a random quantity of CCOS

`mint_percentage := 12.5 + (random() * 5.0)` — the same deposit mints anywhere in a 40%-wide band.
The comment `-- assuming 1 CCOS = $1 for simplicity` fixes a third CCOS price into the mint formula,
against $9 in `credit_voucher_tokens`, $10.13 in `packageOptions.ts:67`, $0.0021 in
`get_total_ecosystem_value`, and `STR × 1000` in `priceUtils.ts:118`.

### I-7. The unstake path burns principal and over-subtracts

`db:process_staking_request`, `request_type='unstake'`:

```sql
UPDATE user_staking_pools
SET staked_amount = GREATEST(0, staked_amount - request_record.amount),
    balance       = GREATEST(0, balance       - request_record.amount)
WHERE user_id = … AND pool_type = … AND staked_amount >= request_record.amount;
```

Three defects in four lines: **(a)** no destination credit — the principal simply vanishes;
**(b)** no `stake_duration_months` or `id` predicate, so the full amount is subtracted from **every**
matching pool (three 100k pools, unstake 50k → 150k destroyed); **(c)** no `lock_end_date` check —
locks do not apply to unstaking at all. The `GREATEST(0, …)` masks the arithmetic error rather than
rejecting it.

### I-8. `process_staking_request` exists twice — and the unused one is the unprotected one

| Overload | APY source | Admin check | Called by |
|---|---|---|---|
| `(uuid, boolean, text)` | delegates to `distribute_enhanced_rewards` → `calculate_dynamic_apy`; the `unique_violation` fallback branch inserts `apy_rate = 0` | **yes** — `IF NOT is_admin(admin_user_id) THEN RAISE EXCEPTION` | **the application** |
| `(uuid, text, text)` | the 70/46/31.5/20/14.75/12 table, plus an `arss` branch | **NONE** | **nothing in the app** |

Three distinct defects:

1. `mig:20251218042835` is titled *"Fix process_staking_request to use CORRECT APY rates"* — and edits
   the overload nobody calls (`audit:§5.3 S5`). The rate fix never reached production behaviour.
2. **The unused overload has no authorization check whatsoever.** It is `SECURITY DEFINER` and,
   under the V1 default, `EXECUTE` to `PUBLIC`. Any caller who passes a `text` third argument instead
   of a `boolean` reaches an unguarded staking approver. Postgres overload resolution decides which
   one runs purely from the argument types the caller sends.
3. The live overload's `unique_violation` fallback writes `apy_rate = 0`, so a stake that hits a
   conflict earns **nothing, forever**, with no error surfaced. And since `mig:20251205142711:3-4`
   dropped the unique constraints the fallback targets, its `ON CONFLICT (user_id, pool_type,
   stake_duration_months)` clause now raises *"there is no unique or exclusion constraint matching
   the ON CONFLICT specification"* — the fallback is dead code that errors rather than recovering
   (§I-26).

That overload also writes `status = 'declined'` (`mig:20251218042835:120`) against a declared
`CHECK (status IN ('pending','approved','rejected'))` (`mig:20250801150446:24`). The CHECK is not
present in the effective schema (the `IF NOT EXISTS` problem, §caveat 4), so the write succeeds and
produces a status value no other code path recognises.

### I-9. `calculate_staking_rewards` uses a different unit convention

`v_apy` is `0.05 / 0.10 / 0.20` and the formula is `(balance × v_apy) / 365` — no `/100`. Every other
function stores `20.0` and divides by 100. If any caller ever treats this function's rates as
percentages the payout is off by 100×. It also returns `0` for 9, 24, 36 and 48 months, and reads
`balance` (principal **+** accrued rewards) rather than `staked_amount`.

### I-10. The live price feed is a random number generator

`fn:str-price/index.ts:15-19`: `0.028 + Math.random() × (0.0318 − 0.028)`, ±13.6% peak-to-peak, on
every request. This is the price the wSTR→fiat cashout consumes (`fn:convert-wstr-to-fiat/index.ts:46,82`),
so a user can retry a conversion until they catch a favourable roll, and the quoted rate is never the
charged rate. The v1 working tree has fixed the *client fallback* to a constant
(`v1:lib/hardenedStr.ts:22`) — **the edge function is untouched, and it is the one that prices money.**

`v2:lib/priceUtils.ts:131,139,147` compounds this by presenting three additional `Math.random()`
perturbations as quotes from CoinPaprika, LiveCoinWatch and CoinGecko.

### I-11. Sixteen of eighteen enhanced pools are invisible

`enhanced_staking_pools.status` is **NULL** on 16 of 18 rows (§B.2). Every consumer filters
`status = 'active'`: the RLS read policy, `distribute_enhanced_rewards` (2025-09-03 version), and the
`process_staking_request` fallback lookup. So the entire published pool ladder — Spark, Pulse,
Momentum, Gravity, Eclipse across all three tokens — cannot be selected. Only `STR Nova Stake`,
`DOMAIN 9m Enhanced` and `DOMAIN 36m Enhanced` are reachable. The frontend nonetheless renders the
full ladder from its own hardcoded tables, so users are quoted pools that do not exist.

### I-12. Node economics are sized for a price the token does not have

STARW pays 2.9 wSTR/node/day (`mig:20260322052154:59`) on a $13,000 node; supernodes pay 27.7
wSTR/node/day (`mig:20260322053054:66`) on a $39,000 node. At the live ~$0.03 STR price that is
**0.24% and 0.78% annually** against an advertised ~11% — the rates only work if 1 wSTR ≈ $1
(`audit:§5.5 P3`). Node prices are themselves dual: $13,000 vs $9,900, and $39,000 vs $50,000.

And the rewards are **unspendable regardless**: they are written to `starw_wstr_rewards` /
`supernode_wstr_rewards`, which no balance function reads and no conversion path touches
(`audit:§3.9` — ~93,600 wSTR stranded across 87 holders).

### I-13. `is_withdrawal_available` has no caller

The one correct lock-check function in the system (`db:is_withdrawal_available`) appears in no edge
function, no migration, and no frontend file. Its third clause (`btc_wallet_locked = true`) would
also block every founder whose wallet flag was never set — nothing on the happy path sets it.

### I-14. The staking withdrawal flow does not exist

`v2:pages/StakingWithdrawals.tsx:254-255` is literally
`// Here you would implement the actual withdrawal logic` followed by a success toast. Withdrawal
addresses live in React state and are never persisted (`:232-235`). The per-token lock table at
`:64-72` (str 90 / ccos 120 / wstr 180 / btc 365 / eth 270 / bnb 90 / domain 90 days) is browser-side
decoration with no server counterpart, and it contradicts `lock_end_date`, which is derived from
`stake_duration_months` (3–48 months). Meanwhile `:160-166` fabricates five mock pools with invented
APYs and merges them into the user's real pool list at `:168`.

### I-15. Emergency-unstake penalties are UI-only

`v2:components/StakingCalculator.tsx:54-59,70` and `v2:pages/Staking.tsx:510` describe a 50%
duration penalty and quantify the forgone reward. **No DB function, migration, or edge function
implements any penalty**, and the unstake branch (§I-7) ignores `lock_end_date` outright.

### I-16. Twelve monetary values are computed in the browser and trusted

See §G.4. Two of them (`founder_pool_transactions`, `currency_exchanges`) write
`status: 'completed'` from client code, and `v2:pages/FounderPool.tsx:406` fabricates the
transaction hash with `Math.random()`. Any user can open the network tab and mint a completed,
arbitrarily-priced, fee-free transaction with a plausible-looking proof of payment.

### I-17. Tiers are a UI with no system behind it

The `user_status` enum (`standard/silver/gold/platinum/vip`) has:
- no threshold logic anywhere — the only writer is `update_user_badge_status(user, status)`
  (`mig:20250801144619:96,110`), driven by four unconditional admin buttons
  (`v2:…/EnhancedUserManagement.tsx:541,548,555,562`);
- no grants — exhaustive grep finds it read only for badge text and badge colour.

The one tier system with real thresholds — `db:update_vip_status` (10,000,000 STR staked **or** 1,000
domains staked) — writes to a *different* table (`vip_users`), is not wired to `user_status`, has **no
cron entry and no caller**, and sums `staked_amount` across phantom pools as if they were real.

### I-18. Affiliate and referral commission has no rate

`seed_str_referrals.commission_amount` and `referrals.reward_amount` both default to `0`. There is no
rate constant, no calculator, and no trigger in the DB, the edge functions, or either frontend. The
admin console displays `commission_amount` as read from the DB
(`v2:pages/AdminSeedStrAffiliates.tsx:522-523`) — a column nothing ever populates.
`referrals` has 0 rows in production (`audit:§4.5`), and the INSERT policy checks only `referred_id`,
permitting self-referral with an arbitrary reward (`audit:§6.3 M8`).

### I-19. `vanquish` is an accepted asset with no implementation

`db:voucher_redemptions_token_type_check` permits `token_type = 'vanquish'`. There is no `vanquish`
pool type (it would fail `user_staking_pools_pool_type_check`), no price, and no branch in
`db:credit_voucher_tokens` — which returns `'Invalid token type'` for it. An approved `vanquish`
voucher is accepted by the table and then silently fails to credit.

### I-20. Node count caps disagree with the sales page

`db:starw_nodes_node_number_check` permits node numbers 1–100. `v1:pages/StarwSale.tsx:16` sells
`TOTAL_NODES_AVAILABLE = 39` and the page copy says "Limited to 39 nodes" (`:291`). Nothing prevents
nodes 40–100 from being created.

### I-21. Ecosystem valuation uses prices from nowhere

`db:get_total_ecosystem_value` values STR at **$1.85** and CCOS at **$0.0021**. STR trades at ~$0.03
in the live feed (62× lower) and CCOS is priced at $9–$10.13 in the voucher path (≈4,500× higher).
The function also values `domain` pool units at the STR price. Any figure it produces is meaningless.

### I-22. `held_balance` has no release path

`fiat_wallets.held_balance` is assigned (not incremented) by `process-fiat-transfer`
(`audit:§5.1 B1`) and is **never decremented anywhere** in the codebase. Every hold is permanent;
`available + held == balance` drifts monotonically. $1,056,727 is currently frozen across 20 wallets
(`audit:§3.9`). The rebuilt DB has no CHECK asserting the identity.

### I-23. Two reward-crediting conventions on the same pools

`db:distribute_vested_rewards` credits `days_to_credit = GREATEST(1, today − last_reward_date)` —
catching up missed days — while `db:calculate_daily_rewards` credits exactly one day and
`fn:manual-rewards-distribution` also credits one day while stamping `last_reward_date = today`,
silently discarding the missed interval (`audit:§5.3 R4/S8`). `db:backfill_historical_rewards` uses a
third convention: it **assigns** `rewards_earned = expected_total` rather than incrementing, so any
reward correctly credited by a different path is erased and re-added, and the arithmetic depends
entirely on which of the four ran last.

### I-24. `db:calculate_daily_rewards` compounds and has no date guard

It computes `balance × apy/100/365` where `balance` already contains every prior reward, and it has
**no `last_reward_date` check and no `lock_end_date` check**. It is still `SECURITY DEFINER` and
RPC-reachable via `db:manual_calculate_rewards`. Every invocation compounds; nothing stops repeated
invocation in a single day.

### I-25. ARSS is stored in two unrelated places

The signup bonus lands in `user_wallets.arss_balance` (`db:create_user_wallet`), while ARSS staking
and voucher credits land in `user_staking_pools` where `pool_type = 'arss'`. Nothing reconciles the
two, and `db:get_available_balance(user, 'arss')` reads only the pools — so the 1,000-ARSS welcome
bonus is invisible to every balance check in the system.

### I-26. The uniqueness that half the system depends on was dropped

`mig:20251205142711:3-4` drops **both** `user_staking_pools_unique_duration` and
`user_staking_pools_user_id_pool_type_stake_duration_months_key`. `pg_constraint` confirms the only
unique left on the table is `PRIMARY KEY (id)`. Consequences:

- `db:process_staking_request`'s `ON CONFLICT (user_id, pool_type, stake_duration_months)` clause can
  no longer resolve and raises at runtime (§I-8).
- `db:credit_voucher_tokens` selects its target pool with
  `WHERE user_id=… AND pool_type=… AND stake_duration_months=3 ORDER BY created_at ASC LIMIT 1` — with
  duplicates permitted, which pool a voucher lands in is now arbitrary.
- `db:initialize_user_staking_pools` guards with `SELECT EXISTS(...)` and then `INSERT` — a
  check-then-act race with no constraint behind it, so two concurrent sessions create duplicate
  empty pools (`audit:§5.4 S7`).
- Every aggregate over `user_staking_pools` (VIP qualification, `get_available_balance`, ecosystem
  value, the admin dashboards) silently double-counts duplicated rows.

### I-27. The two voucher paths price STR 1.8× apart

`mig:20260305062237_ca9712eb…:2-3,68-74` changes the STR voucher rate to **$0.005/STR** —
*"Previously used $0.00911/STR. Changed to $0.005/STR for March 1-15, 2026 promotional vesting
period. CCOS remains at $9/token, ARSS remains at $0.00911/token."* — inside
`admin_correct_voucher_tokens`. But `db:credit_voucher_tokens`, whose latest version is
`mig:20260508055202` (**two months later**), still prices STR at **`0.00911`**. So the crediting path
and the correcting path disagree by 1.82×: every correction run against a legacy-format voucher moves
the balance to a different number than the crediting path would have produced, in both directions
depending on which ran last. Neither is marked authoritative.

Pre-CEX vouchers add a **third** STR price: the fixed table in `db:credit_voucher_tokens` implies
$250 → 166,666 STR ≈ **$0.0015/STR**.

### I-28. `convert_wstr_to_fiat_atomic` takes the fiat amount from its caller

The atomic conversion function (`db:convert_wstr_to_fiat_atomic`, `mig:20260706053425:11`) correctly
row-locks, re-reads the wSTR balance inside the lock, and refuses an overdraw. It then credits
`fiat_wallets` with `p_fiat_amount` — **a value supplied by the caller**. The rate table that its
predecessor `db:convert_wstr_to_fiat` applied server-side (EUR 0.92 / GBP 0.79 / CHF 0.88) is not
applied here. The only caller, `fn:convert-wstr-to-fiat/index.ts:82`, computes
`wstr_amount × wstrPriceUSD × forexRate` in JavaScript floats, where `wstrPriceUSD` is the random
number from `fn:str-price` (§I-10). So the debit side is atomic and verified; the credit side is a
float computed against a random price. The function is safe against double-spend and unsafe against
mispricing.

The superseded `db:convert_wstr_to_fiat` still exists, still assumes **1 wSTR = 1 USD**, and **never
credits `fiat_wallets` at all** — it only writes the debit row. It has zero callers
(`audit:§7.4`) and should be dropped; while it exists it will keep misleading anyone reading the
schema for the conversion rule.

### I-29. `arss_transactions` — the main ledger — has no constraints at all

No CHECK on `transaction_type`, no CHECK on `amount`, no trigger. The `validate_transaction_amount`
trigger that enforces `amount > 0` is attached to `wallet_transactions`, **not** to
`arss_transactions` (`mig:20251101122157:78-136`). At least ten distinct `transaction_type` strings
are written across the migration history (`stake`, `reward`, `earn`, `staking_reward`, `debit`,
`credit`, `voucher_redemption`, `balance_correction`, `manual_credit`, `voucher_correction`) and
`db:get_user_wstr_balance` recognises six of them (§I-3). A typo in a type string produces a silently
inert ledger row, and a negative `amount` on a `credit` row silently debits.

### I-30. Local rebuild diverges from production on authorization

Stated again because it is the easiest mistake to make with this environment: the local DB's
`user_staking_pools` policies (`recovered own insert` / `recovered own update`, permitting any user to
insert and update their own pool rows) are generated by `scripts/gen-recovered-schema.mjs:402` and
**survive** the production lockdown at `mig:20260509121934:11-13`, which drops policies by their
production names. Any authorization conclusion drawn from the local DB is wrong. Migrations are the
only valid source for RLS.

---

## Appendix: the paths that are correct

Worth preserving as the model for any rebuild.

| Path | Why it is right |
|---|---|
| `db:transfer_staking_pool_atomic` | `SELECT … FOR UPDATE` + relative `SET balance = balance ± amount`; refuses self-transfer and non-positive amounts; returns false rather than partially applying |
| `db:debit_staking_pool_balance` | Row-locked, relative decrement, fails closed |
| `db:convert_wstr_to_fiat_atomic` | Locks the user's ledger rows, recomputes the balance inside the lock, inserts the debit and credits fiat in one transaction |
| `db:enforce_precex_str_voucher_lock` | A real lock: blocks balance, principal, status, type and APY changes and DELETE while vesting, and refuses to shorten the lock |
| `db:distribute_starw_wstr_rewards` / `db:distribute_supernode_wstr_rewards` | `UNIQUE(node, date)` plus a `NOT EXISTS` guard makes them idempotent per day — the only reward paths that cannot double-credit |
| `db:validate_staking_balance`, `db:validate_transaction_amount` | Actual triggers, actual `RAISE EXCEPTION` |
| `fn:submit-staking-request` | Zod schema server-side, amount ceiling, domain-duration rule, internal-payment restriction — the one purchase path the browser cannot forge |
| `…/ccoin-bank-ccos-fee/index.ts` | Fee schedule and conversion rates held server-side, fee deducted server-side, ledger row written, fee linked back to the originating transfer |
