# IgniteHeX — Architecture Review and Roadmap

**Date:** 2026-08-18
**Trees reviewed:** `c:/tmp/ignitehex-v2` (V1 platform), `c:/tmp/ignitehex-v3` (rebuild),
`c:/tmp/ignitehex-selfhost` (self-hosted stack), with `C:/Users/strho/hex-ignite-nexus` as the
working repo that holds the audit.

---

## 0. The recommendation, first

**v3's architecture is right and v3 is not usable, and those two facts have one cause.** The rebuild
correctly refused to move money from the browser, but nothing was built on the server to take over.
Forty-five member and operator actions are rendered visibly disabled with a named missing routine.
They collapse into **seven routine families**, and one family — *a credit counterpart to the debit
functions that already exist* — unblocks roughly a quarter of them on its own.

Three things must be true before this platform can carry real money again, in this order:

1. **A double-entry ledger with a credit primitive.** Today the database has
   `debit_staking_pool_balance` and `debit_fiat_wallet` and **no credit counterpart**. Every
   half-finished money path in v3 traces back to that asymmetry.
2. **The unauthenticated `process_staking_request` overload must be closed.** v3 calls it today
   (§1.4). It is the one live privilege-escalation path the rebuild inherited rather than removed.
3. **One APY source and enforced supply caps.** Fifteen disagreeing APY tables and caps that exist
   only in prose are why the audit's headline numbers are what they are.

Everything else — the self-hosted stack, the PGlite build, the design system, the domain contract —
is scaffolding quality and can be improved in parallel without blocking.

**The trade-off this review accepts:** I am recommending you build the server surface *before*
re-enabling any of the 45 controls, rather than shipping a subset behind feature flags. That costs
several months during which v3 looks less capable than v2. What it buys is that v3 never repeats the
class of failure that produced 2.49B cashable wSTR against 49.2M actually earned. A platform that
does less but tells the truth is recoverable; one that reports success on writes RLS silently
dropped is not.

---

## 1. CURRENT STATE

### 1.1 What each tree is

| Tree | Size | State | Verdict |
|---|---|---|---|
| `ignitehex-v2` | 723 migrations, 94 edge functions, 175 tables, 185 RPCs, 634 src files, 139 routes | Deployed, carrying real members | **Production, and compromised** |
| `ignitehex-v3` | 125 files, ~49,900 lines, 11 domains, 50 domain routes | Reads real data; writes almost nothing | **Working scaffolding, not a product** |
| `ignitehex-selfhost` | 9 files, 8 containers | Runs; no README, not a git repo | **Development fixture only** |

### 1.2 v2 — what is real

v2 is a real platform with roughly 6,400 investors (`hex-ignite-nexus/docs/MASTER_AUDIT.md:16`).
The account base, IBAN table and voucher ledger are clean where it counts. The damage is
concentrated in money-handling logic, and it is measured, not estimated
(`MASTER_AUDIT.md:296-312`):

- 2,486,189,965 cashable wSTR booked against 49.2M actually earned in pools — **54×**.
- 1,026,018,564 CCOS held against a 63,000,000 cap — **16.3×**, 97% of it one account.
- €402,050,930 in fiat-wallet balances booked as withdrawable and unbacked.
- −9,396,884,459 wSTR of clawbacks written that have **zero effect**, because they use transaction
  types `get_user_wstr_balance()` never sums.

The containment window is open: actual external bank outflow is ≈€200K pending, ≈€0 completed
(`MASTER_AUDIT.md:31`). The paper liability has not become cash loss.

**v2's structural problems, quantified:**

- **97.5% of migrations are machine-named.** 705 of 723 carry a UUID suffix; only three have
  intentional names. Fifteen more are degenerate stubs with an empty suffix
  (`ignitehex-v2/supabase/migrations/20250813032736-.sql` and fourteen siblings).
- **The schema is not reproducible from its own migrations.** `migration-replay-report.json:2-4`
  claims `"total": 723, "applied": 723, "failed": 0`. Per-entry, 647 are truly clean, **41 are
  `ok:true` with a recorded SQL error and `skipped: "data-only"`**, and 35 needed a retry (30 after
  dropping an existing function, 5 with FK enforcement deferred). 76 migrations — 10.5% — did not
  replay cleanly. `failed: 0` is an artifact of `ignitehex-v2/scripts/rebuild-local.mjs:275`
  returning `ok: true` for a migration that threw.
- **27 of 94 edge functions have `verify_jwt = false`**, and at least 13 of those move money
  (`ignitehex-v2/supabase/config.toml:7,10,16,19,106,109,115,126,129,150,153` and others). Six of
  the ones I read have no role check in code either; four never resolve a user at all.
  `process-fiat-transfer` authenticates any signed-in user and then operates with the service-role
  client with no ownership gate (`supabase/functions/process-fiat-transfer/index.ts:36-55`).
- **`api-v1`** (977 lines, exposes wallets and balances) takes a custom `x-api-key`, SHA-256s it
  with no salt, and **truncates the hash to 32 hex characters** — 128 bits
  (`supabase/functions/api-v1/index.ts:30-35`).
- **Config coverage is 60%.** 37 deployed functions have no `config.toml` entry (defaulting to
  `verify_jwt = true`, the safe direction), and 2 config entries name directories that do not exist.
- **139 routes, zero `lazy()` calls.** All 114 pages are statically imported into one bundle.

### 1.3 v3 — production-ready, scaffolding, and stub

**Production-ready.** These are genuinely better than v2 and should be kept as-is:

- **The domain contract.** `src/domains/types.ts:19-43` and `src/domains/registry.ts:29-42` make a
  domain declare its own routes, nav entries and role requirements, and
  `src/routes/DomainRoutes.tsx:16-51` derives all three from that one declaration. A route is
  guarded because it said it needed a role, not because a page remembered. v2's eight unguarded
  admin pages are structurally impossible here.
- **One balance definition.** `src/lib/balances.ts:47-73` folds pools into one position per token,
  reading `staked_amount` and `balance` as independent numbers. `fetchAvailable` returns `null`, not
  `0`, on failure (`:80-89`) — v2 collapsed both and displayed a member's whole holding as locked
  after one failed request.
- **One design system.** 53 semantic tokens in `src/index.css`, light and dark defined in the same
  place, three type faces. v2 had accumulated four, and the Dome prototype would have been a fifth.
- **Honest query state.** `src/lib/query.ts:11-32` gives the app one client with real invalidation;
  v2 mounted a `QueryClientProvider` and used it in one of ~1,136 call sites. `Async` /
  `AsyncSection` (`domains/investments/shared.tsx:73-93`, `domains/banking/shared.tsx:33-56`)
  distinguish "nothing yet" from "we could not load this".
- **Explicit column lists.** `src/hooks/data.ts:14-20` — no `select('*')` on tables carrying
  encrypted PII. v2 had 229 star-selects.

**Scaffolding — correct shape, not yet load-bearing:**

- **The write surface is 51 direct table writes and 30 RPC calls**, and with two exceptions none of
  them touches a balance. The exceptions are `debit_staking_pool_balance`
  (`domains/marketplace/hooks.ts:680`) and `process_staking_request`
  (`domains/staking/hooks.ts:466`). Everything else writes applications, listings, votes, messages
  and configuration.
- **The escrow path is client-orchestrated.** `domains/marketplace/hooks.ts:655-745` runs four
  sequential steps: insert listing → debit pool → insert escrow row → publish. It handles each
  failure honestly (it marks the listing `escrow_error` and raises a custom
  `EscrowInconsistencyError` naming the listing id), which is far better than v2. It is still a
  browser orchestrating a money movement across four round trips, and step 3 failing leaves tokens
  debited with no escrow record and no automated reversal.
- **Six independent copies of the same primitive.** `BlockedAction`
  (`domains/marketplace/shared.tsx:42`), `LockedAction` (three separate definitions at
  `domains/investments/shared.tsx:102`, `domains/guardian/shared.tsx:17`,
  `domains/bonuses/shared.tsx:98`), `ServerActionPending` (`domains/banking/shared.tsx:161`) and
  `UnavailableAction` (`domains/admin/components.tsx:211`). Same idea, four names, six
  implementations, three different visual treatments. This is the one place v3's "one design system"
  claim is already untrue.
- **SAFE MODE is a `localStorage` flag.** `domains/admin/lib/safeMode.ts:23-45`. The comment at
  `:24-25` is right that "a `disabled` attribute is a hint to a human, not a control" — and then
  implements the control in browser storage anyway. It is a good operator ergonomic and it is not a
  security boundary; anyone who can call the RPC can set `voucher_safe_mode = 'off'` first, or skip
  the UI entirely.

**Stub / absent:**

- **No tests, no CI, not a git repository.** No `*.test.*`, no `.github`, `git log` fails.
- **`package.json` declares zero dependencies.** `ignitehex-v3/package.json` has `scripts` and
  nothing else, while `src/` imports react, react-router-dom, `@supabase/supabase-js`,
  `@tanstack/react-query`, `lucide-react`, `sonner` and Tailwind. The 673-package `node_modules`
  present in the tree carries Capacitor, Coinbase, ethereumjs and Ionic — it is v2's, inherited by
  copy. **`npm install` in a clean checkout produces a tree that cannot build.** This is the single
  cheapest thing to fix on this list and it blocks CI entirely.
- **A service-role key sits in `ignitehex-v3/.env.local`.** It is not `VITE_`-prefixed, so Vite will
  not bundle it — the immediate risk is contained. It should still not live in the frontend tree.
- **The SQL test harness exists and has no tests.** `hex-ignite-nexus/scripts/run-sql-tests.mjs` is
  well designed — each file a self-contained transaction ending in `ROLLBACK`, with a convention
  that tests named RED assert behaviour the code does not yet have and their failure text *is* the
  finding. `tests/sql/` contains no `*.test.sql` files.

### 1.4 The one live defect v3 inherited rather than removed

**v3 calls the unauthenticated overload of `process_staking_request`.**

`src/domains/staking/hooks.ts:466` calls it with `{ p_request_id, p_action, p_admin_notes }` — the
`(uuid, text, text)` signature. Both overloads are present in the generated types
(`src/lib/database.types.ts:10542-10554`). Per `docs/PLATFORM_RULES.md:818-828`:

| Overload | Admin check | Called by |
|---|---|---|
| `(uuid, boolean, text)` | **yes** — `IF NOT is_admin(admin_user_id) THEN RAISE EXCEPTION` | v2 |
| `(uuid, text, text)` | **NONE** | **v3** |

It is `SECURITY DEFINER` and, under the V1 default, `EXECUTE` to `PUBLIC`. Postgres resolves the
overload purely from the argument types the caller sends, so passing a `text` third argument reaches
an unguarded staking approver — one that inserts a `user_staking_pools` row and sets its APY.

v3's own comment directly above the call (`src/domains/staking/hooks.ts:449-452`) states: *"The RPC
runs with the authorisation check and the APY schedule inside the database."* For this overload that
is false. The route is guarded by `requiresRole: 'admin'`
(`src/domains/staking/index.ts:44`), which by this platform's own ground truth is ergonomics, not
security — the RPC is reachable over PostgREST without the UI.

**This is the highest-severity finding in this review, and it is in the rebuild, not the legacy
system.** It is also cheap to fix: switch the call to the `(uuid, boolean, text)` overload, then
`REVOKE EXECUTE … FROM PUBLIC, anon, authenticated` on the `(uuid, text, text)` one — or drop it.

### 1.5 `TODO(server)` census

**32 markers** across `v3/src/domains`, attached to **45 disabled controls** (43 rendered through
the blocked-action components, 2 as plain disabled buttons). Distribution:

| Domain | Markers | Disabled controls |
|---|---|---|
| marketplace | 7 | 9 |
| banking | 1 | 13 |
| investments | 7 | 9 |
| guardian | 3 | 5 |
| admin | 5 | 5 |
| bonuses | 3 | 1 (+2 safe-mode gates) |
| staking | 1 | 1 |
| wallet | 1 | 1 |

Banking's ratio is worth noting: one marker, thirteen controls. The domain documented the gap once
in prose and then disabled everything downstream of it — which is correct behaviour and means the
marker count understates the gap. The reverse is true in admin, where three of the five markers are
deliberate *non*-requirements (see Group G below).

---

## 2. THE SERVER GAP

This is the central architectural problem. v3 removed the browser's ability to move money and
nothing replaced it. Below, every disabled control grouped by the routine that would satisfy it,
ranked by how much each routine unblocks.

### Group A — the missing credit counterpart · **11 controls · rank 1**

`debit_staking_pool_balance` and `debit_fiat_wallet` both exist, are row-locked, use relative
decrements and fail closed — `docs/PLATFORM_RULES.md:1058-1060` lists them among the paths that are
*correct*. **Neither has a credit counterpart.** Every value transfer therefore has a working
first half and no second half, which is worse than having neither.

The code says this repeatedly and independently:

- `domains/marketplace/Sell.tsx:320-330` — *"Migration 20260509121934 revoked user UPDATE on
  user_staking_pools and shipped only `debit_staking_pool_balance` — there is no credit counterpart,
  so nothing here can put the tokens back."*
- `domains/marketplace/Merchant.tsx:606-616` — *"`debit_fiat_wallet` covers only the payer's leg —
  there is no credit counterpart — so a client-side implementation would take the customer's money
  and never deliver it."*
- `domains/marketplace/Merchant.tsx:630-634` — *"`debit_fiat_wallet` handles the debit with a row
  lock but nothing credits the beneficiary, so a failure after the debit loses the money outright."*

| Control | Site | Named routine |
|---|---|---|
| Cancel listing (return escrow) | `marketplace/Sell.tsx:338` | `release_marketplace_escrow(p_listing_id)` |
| Buy (settle token purchase) | `marketplace/Browse.tsx:389` | `settle_token_listing(p_listing_id, p_buyer_id)` |
| Take a payment (POS) | `marketplace/Merchant.tsx:623` | `settle_pos_charge(p_reference_id)` |
| Send from IBAN | `marketplace/Merchant.tsx:638` | IBAN-to-IBAN transfer |
| Send money to another member | `banking/Transfers.tsx:307` | `process-fiat-transfer` |
| Claim released commission | `bonuses/Referrals.tsx:204` | `claim_referral_rewards(p_referral_ids uuid[])` |
| Withdraw commission | `investments/RewardsPage.tsx:340` | `settle-affiliate-commission` |
| Approve and credit (airdrop) | `bonuses/Admin.tsx:682` | `approve_airdrop_registration(p_registration_id, p_amount)` |
| Approve and credit (airdrop, admin) | `investments/AdminPage.tsx:648` | `credit-airdrop-registration` |
| Credit or adjust a member balance | `banking/Admin.tsx:465` | double-entry adjustment with reason code |
| Release a held treasury transfer | `banking/Admin.tsx:469` | debit + credit + CCOS fee in one txn |

**What to build.** Not eleven functions — one ledger. A `post_entries(entries[])` primitive that
takes a balanced set of debits and credits, locks the affected rows in a deterministic order,
refuses to commit unless the set sums to zero, writes one ledger row per leg with an idempotency
key, and returns the resulting balances. The eleven routines above become thin callers of it. Build
it once and Group A closes; build eleven separate functions and you have reproduced v2's 185-RPC
surface with the same drift.

The two existing debit functions are the model for the locking discipline — reuse it. Note that both
were only made caller-safe on 2026-08-18, and by **string-rewriting `prosrc` inside a `DO $splice$`
block** (`ignitehex-v2/supabase/migrations/20260818120100_v3_guard_debit_functions.sql:30-43`). That
patches whatever body happens to be installed. It works; it is not something to build more on.

### Group B — decision and credit as one statement · **6 controls · rank 2**

Every one of these is an operator approving something that moves value. The decision and the credit
must be the same transaction, or the two diverge exactly as they did in v2.

| Control | Site | Named routine |
|---|---|---|
| Approve / decline seed application | `investments/AdminPage.tsx:459` | `review-seed-str-application(application_id, decision, notes)` |
| Approve / decline private seed | `investments/AdminPage.tsx:550` | same function |
| Reject or suspend bank application | `banking/Admin.tsx:264` | `process-ccoin-bank-approval` + an `action` parameter |
| Start a seed application | `investments/ApplicationsPage.tsx:106` | `submit-seed-str-application` |
| Subscribe (7 of 8 offerings) | `investments/OfferingsPage.tsx:128` | per-offering; see `investments/constants.ts:305-391` |
| Approve airdrop registration | `bonuses/Admin.tsx:682` | shared with Group A |

`process-ccoin-bank-approval` is the sharpest example: it implements approval and **has no reject
branch at all**. v2 rejected by updating `ccoin_bank_applications.status` from the browser, leaving
no server-verified record of who decided (`banking/Admin.tsx:266`). Adding a parameter to one
existing function unblocks that control.

Seven of eight offerings are blocked (`investments/constants.ts:315-391`). That is the investment
product, closed.

### Group C — external settlement · **8 controls · rank 3**

These need something that talks to a chain or a payment rail and records what it returned. A browser
cannot do either half.

| Control | Site | Named routine |
|---|---|---|
| Withdraw to external wallet | `staking/StakingWithdrawals.tsx:261` | `process-staking-withdrawal` |
| Approve / Mark sent / Reject | `guardian/Withdrawals.tsx:407,412,417` | `guardian-process-withdrawal` (one function, three decisions) |
| Cancel a request | `guardian/Withdrawals.tsx:345` | `guardian-cancel-withdrawal` |
| Execute founder withdrawal | `investments/PositionsPage.tsx:296` | `execute-founder-withdrawal` |
| SEPA / SWIFT payout | `banking/Transfers.tsx:311` | payout fn with sanctions screening |
| Refund a held transfer | `banking/Transfers.tsx:315` | `request-transfer-refund` |

`guardian/Withdrawals.tsx:388-400` already specifies the whole function — approve reserves against
the vault and stamps `processed_by` from the token *never from a client field*; complete broadcasts,
stores the returned `tx_hash`, then sets status. Build to that spec.

Two of these are worth calling out because v2's version was actively dangerous.
`guardian/Withdrawals.tsx:330-338`: the table has no owner UPDATE policy, so v2's client-side
`update({ status: 'cancelled' })` was filtered to zero rows by RLS, returned success, and v2 patched
local state so the row *looked* cancelled until reload. And `investments/PositionsPage.tsx:281-291`:
v2's founder deposit wrote a `transaction_hash` built from `Math.random()` and marked the row
`completed`. A reference that is not a real transaction is worse than none.

`is_withdrawal_available` implements the founder lock correctly and **has no caller**
(`PLATFORM_RULES.md:883-887`). v3 calls it (`domains/staking/hooks.ts:331`) — for display. Wire the
server-side check to the same function.

### Group D — issuance and provisioning · **10 controls · rank 4**

Minting an identifier and opening a ledger row at zero. Lower rank because nothing is stolen while
these stay disabled — the product is merely absent.

| Control | Site | Named routine |
|---|---|---|
| Open an account (IBAN) | `wallet/Accounts.tsx:244` | `create_iban_for_user(p_user_id, p_country, p_currency, p_account_type)` |
| Open an additional currency account | `banking/Accounts.tsx:248` | single-member counterpart to `bulk-provision-banking` |
| Close or suspend an account | `banking/Accounts.tsx:252` | residual balance + holds + authoriser |
| Request business IBAN | `marketplace/Merchant.tsx:562` | `issue_merchant_iban(p_merchant_id, p_currency)` |
| Mint STR domain | `marketplace/Domains.tsx:316` | `mint_str_domain(p_domain_id)` |
| Freeze / unfreeze card | `banking/Cards.tsx:506` | card status fn |
| Order a physical card | `banking/Cards.tsx:510` | address validation + shipping price + consent |
| Top up from encrypted account | `banking/Cards.tsx:514` | `submit-card-topup` taking an `iban_accounts.id` |
| Founder deposit | `investments/PositionsPage.tsx:207` | `founder-pool-deposit` |
| Order STARW nodes | `investments/PositionsPage.tsx:474` | `submit-starw-purchase` |

The IBAN entries are the ones to build first, because v2's version let a client mint itself a bank
account: it generated the IBAN in the browser and inserted the row directly
(`wallet/Accounts.tsx:238-243`), and the merchant path built one from `Math.random()` with uncomputed
check digits and inserted the `balance` column too — a self-declared opening balance
(`marketplace/Merchant.tsx:553-559`).

Founder deposit deserves its own note: v2 did four operations from the browser against a stale
in-memory pools array, so two concurrent deposits lost one (`investments/PositionsPage.tsx:193-201`).
It also calls `calculate_ccos_mint`, which issues `12.5 + random() * 5.0` percent — **the same
deposit mints anywhere in a 40%-wide band** (`PLATFORM_RULES.md:794-799`). Do not rebuild this
routine around that function.

### Group E — multi-row settlement · **3 controls · rank 5**

| Control | Site | Named routine |
|---|---|---|
| Accept a bid | `marketplace/Activity.tsx:114` | `accept_domain_bid(p_listing_id, p_bid_id)` |
| Mark invoice paid | `marketplace/Merchant.tsx:652` | `settle_invoice(p_invoice_id, p_payment_reference)` |
| Reserve | `marketplace/Browse.tsx:457` | per-listing platform escrow address from the server |

Accepting a bid is four writes, three of them on rows owned by other members. v2 fired them one
after another; RLS silently dropped the writes to other bidders' rows, so losing bidders stayed
`pending` forever (`marketplace/Activity.tsx:103-113`). This *cannot* be done client-side under any
RLS policy that is also correct — it is the cleanest possible argument for the service-role RPC.

`Reserve` is a different shape: v2 fell back to hardcoded `ADMIN_BTC_WALLET` / `ADMIN_ETH_WALLET`
constants, silently redirecting the buyer's money to an address the seller never agreed to
(`marketplace/Browse.tsx:445-455`). Fixing this needs a data model change — a payout address per
listing — not just a function.

### Group F — key custody · **2 controls · rank 6**

| Control | Site | Requirement |
|---|---|---|
| Reveal full IBAN | `banking/Accounts.tsx:244` | decrypt server-side, write an access-audit row, return one view |
| Confirm / reject encrypted IBAN data | `banking/Admin.tsx:473` | needs the encrypted values, readable only by a key-holding function |

Small, well-specified, and independent of the ledger work. `iban_accounts` has a BEFORE trigger that
masks the plaintext columns, so the browser sees `***ENCRYPTED***` and confirmation is impossible
client-side by construction. Good — that trigger is doing its job.

### Group G — operator state with nowhere to live · **5 controls · rank 7**

| Control | Site | Note |
|---|---|---|
| Mark finding as triaged | `admin/Risk.tsx:333` | Findings are recomputed per scan and never stored. Needs a findings table. |
| Freeze wallet | `admin/Risk.tsx:338` | `freeze_wallet` setting a hold without the client naming an amount |
| Change margin policy | `guardian/Alerts.tsx:324` | `guardian-set-margin`: validate band, actor from JWT, version the prior rule |
| Bulk-fix balances | `admin/Corrections.tsx:436` | Blocked *correctly* — see below |
| Undo a revert | `admin/Corrections.tsx:446` | Needs `admin_revert_position_correction` to write its own `before_data` |

Two of these are deliberate refusals rather than gaps, and they are the best judgement calls in the
tree. `admin/Corrections.tsx:439` declines to call `bulk-fix-balances` because that function expects
a client-supplied list of expected-versus-actual amounts — *"Sending it a list this console computed
would mean the browser choosing the balances."* That is exactly right, and it is precisely the
mechanism the audit blames for the recurring correction cycle: `MASTER_AUDIT.md:160` records that
`fix-user-balance` and `bulk-fix-balances` **DELETE the pool and re-insert a client float**, erasing
`rewards_earned`, the staked/reward split and concurrent credits — *"the fixers re-seed the drift
they patch."* And `admin/Corrections.tsx:444` declines a write-off routine on the grounds that the
normal correction already scales an uncredited account to zero. Keep both refusals.

`freeze_wallet` should be pulled forward out of rank order. It is the containment primitive — the
thing an operator reaches for when the risk console surfaces a negative or mismatched wallet. Right
now the only available containment is quarantining the member on a different screen.

### 2.1 Ranking summary

| Rank | Routine family | Controls | Effort | Unblocks |
|---|---|---|---|---|
| 1 | Ledger + credit primitive | 11 | High | Every transfer, sale, payout and reward credit |
| 2 | Decision-and-credit review routines | 6 | Medium | The entire investment product |
| 3 | External settlement / broadcaster | 8 | High | Withdrawals, the vault, fiat payouts |
| 4 | Issuance and provisioning | 10 | Medium | Banking as a product |
| 5 | Multi-row settlement | 3 | Low–Medium | The marketplace's auction half |
| 6 | Key custody | 2 | Low | IBAN visibility and confirmation |
| 7 | Operator state | 5 | Low | Risk triage, containment, margin policy |

Groups 1 and 3 share a dependency: both need the ledger before they mean anything, because a
withdrawal that debits without a ledger entry is the same defect as a transfer that credits without
one.

---

## 3. DATA MODEL RISKS

### 3.1 Money representation

**Correct the framing first.** The brief calls this "float-vs-integer money representation (audit
R2)". Two things are off, and the disagreement is itself the finding:

- **R2 is not this finding.** `MASTER_AUDIT.md:150` — S2/R2 is *"Each reward double-credited into
  two spendable stores."* The float finding is **B7/R8** (`MASTER_AUDIT.md:177`).
- **It is not float-versus-integer in the database.** Across all 723 migrations there are **zero**
  occurrences of `double precision`, `float8` or `real` as a storage type. 310 money-named columns
  are `numeric` — exact. The problem is narrower and different: **`numeric` with no
  precision or scale** (842 bare `numeric` declarations against **5** with `numeric(p,s)`), and
  IEEE-754 doubles at the two boundaries the database does not control.

`docs/PLATFORM_RULES.md:92-104` states it precisely: *"There is no fixed-point discipline anywhere,"*
with three mutually incompatible conventions in code — raw `numeric` units in DB and edge functions,
micro-units (`× 1e6`) in v2's `lib/tokenUtils.ts:14,32,44-45,54`, and IEEE-754 float in
`process-swap`, `manual-rewards-distribution`, `convert-wstr-to-fiat` and `process-fiat-transfer`.

The client boundary makes it worse: v2's generated types declare **217 money-named fields as
`number`**, so every balance becomes a JS double regardless of the exactness of its storage. That
matters directly here — the audit's largest single position is 1,000,000,000 CCOS, and a
`numeric(20,8)` value of that magnitude does not survive a round trip through a double.

**What a correct design looks like.** Integer minor units, in `bigint`, with the scale fixed per
asset in an asset register table — not a per-column decision. Fiat at 2 decimals, tokens at 8. The
API returns strings, never numbers, and the client formats from the string. `numeric(p,s)` is the
acceptable second choice for storage, but it does not fix the transport, and the transport is where
half the loss is.

**Migration cost — the honest version.** This touches 310 columns across ~175 tables, 185 RPCs, 94
edge functions and every read site in both frontends. It is not a migration; it is a rewrite of the
data layer. Realistically:

1. **Now, cheap:** add `numeric(p,s)` to the ~20 columns on the tables the ledger will actually
   touch, and add `CHECK (>= 0)` alongside. Bounded, testable, no client change.
2. **With the new ledger:** make the ledger table integer-minor-unit from birth. It is new, so it
   costs nothing. Balances become derived from it rather than stored.
3. **Long term:** the remaining ~290 columns migrate table by table as each domain's routines are
   built, or never — many of them are on tables that should not survive the rebuild anyway.

Do not attempt (3) as a project. The cost is enormous and the benefit accrues only where money
actually moves, which is what (1) and (2) already cover.

### 3.2 The APY sources

**Fifteen, not three.** Nine server-side (`PLATFORM_RULES.md:174-277`) and six in v2's frontend
(`:279-298`). Nothing reconciles any of them.

The sharpest contradictions:

- **Two functions use incompatible units.** `calculate_staking_rewards` stores `0.05 / 0.10 / 0.20`
  and computes `(balance × apy) / 365` with **no `/100`**, while every other function stores `20.0`
  and divides by 100 (`PLATFORM_RULES.md:206-215`). A caller that treats one as the other is off by
  100×. It also returns **0** for 9, 24, 36 and 48 months, and reads `balance` (principal + accrued
  rewards) instead of `staked_amount`.
- **A one-off `UPDATE` beat the function that was supposed to be canonical.**
  `mig:20251218042415:6-15` wrote APY values onto *rows*, hours before `mig:20251218042835`
  redeclared the function. Domain 48-month pools it touched pay **35%**; the function says **82.5%**
  for the same pool (`PLATFORM_RULES.md:264-274`).
- **The rate fix landed on the overload nobody called.** `mig:20251218042835` is titled *"Fix
  process_staking_request to use CORRECT APY rates"* and edits the `(uuid, text, text)` overload —
  the one v2 never invoked (`PLATFORM_RULES.md:824-826`). The fix never reached production
  behaviour. **v3 now calls that overload** (§1.4), so v3 is the first consumer of a rate table that
  has never been reconciled with anything.
- **`calculate_dynamic_apy` is token-blind.** Its own body comments *"assuming STR for now"* and
  then ignores `token_type` entirely, so a CCOS or DOMAIN enhanced stake gets the STR curve
  (`PLATFORM_RULES.md:196-204`). v3 calls this function at `domains/staking/hooks.ts:303`.
- **The admin console disagreed with the database in both directions.**
  `v2:pages/SuperAdminDash.tsx:58-64` over-reports 3-month STR by 25%, under-reports 48-month by
  14%, and shows 36-month as **0** against an actual 46%.

**What a correct design looks like.** One table — `apy_schedule(asset, duration_months,
rate_bps, effective_from, effective_to)` — with rates in **basis points as integers**, so the
unit ambiguity that produced the 100× hazard cannot recur. Every function reads it; no function
carries a `CASE`. A pool stores the `apy_schedule` row id it was priced from, not a copied rate, so
the rate a member was promised is always reconstructable. The frontend reads the same table.

**Migration cost.** Building the table and repointing the functions is a week or two. **Deciding
what the rates should be is a business decision, not an engineering one, and it is blocking** — you
cannot reconcile fifteen tables by picking one, because members hold positions priced under several
of them. The staged approach: freeze new pricing to one schedule immediately; leave existing pools
on their recorded rate; add the schedule-id column; backfill it from the migration history where
determinable and flag the rest for manual reconciliation. Expect a meaningful minority to be
undeterminable — `mig:20251218042415` overwrote rows without recording what they had been.

### 3.3 Supply caps

Caps exist as prose only. `PLATFORM_RULES.md:783-792` and `:633-641`: grepping `63000000`,
`max_supply` and `total_supply` across all migrations **and** all edge functions returns **zero
hits**. Nothing can detect a breach, let alone prevent one. CCOS is 16.3× over.

`enhanced_staking_pools.tvl_cap` is the one place a cap was designed in — the column exists
(`mig:20250720000000:668`) and is never read or written by anything.

The `CHECK (>= 0)` picture is nearly as thin: **11 such clauses in 63,110 lines of SQL**, of which 6
guard money, and the main wallet and staking balance tables have **no database-level floor**.
`fiat_wallets` is the instructive case — `mig:20251025052024:6-8,40-42` *declares*
`CHECK (balance >= 0)`, but does so inside a `CREATE TABLE IF NOT EXISTS` against a table that
already existed, so **the statement is a no-op and the constraint does not exist**
(`PLATFORM_RULES.md:650`). The migration set contains constraints that were written, reviewed,
merged, and never applied.

**What a correct design looks like.** Three layers, cheapest first:

1. **A `CHECK (>= 0)` on every balance column.** Not a design question. Blocked only by existing
   negative rows, which must be surfaced and decided on first.
2. **An `asset_supply` table with a `cap` column, and a constraint trigger** on every minting path
   that fails the transaction when issuance would cross it. Ties naturally to the ledger from §2 —
   if every credit is a ledger entry, the cap check is one aggregate over one table.
3. **A daily reconciliation job** asserting Σ ledger == Σ balances per asset, writing a finding when
   it does not. This is what `admin/Risk.tsx` should be reading instead of recomputing findings that
   have nowhere to be stored (Group G).

**Migration cost.** Layer 1 is days of engineering and an unknown amount of data remediation —
unknown because nobody has counted the violating rows. Layers 2 and 3 are a few weeks and largely
free if built alongside the ledger. **The real cost is not technical.** Enforcing a 63,000,000 CCOS
cap against 1,026,018,564 CCOS held means deciding what happens to 963,018,564 CCOS that provably
should not exist, 97% of it in one account. That is a legal and commercial decision. Engineering can
prepare it — the reversible staged scripts already exist at
`hex-ignite-nexus/docs/cleanup/` — but it cannot make it.

### 3.4 A fourth risk the brief did not name: no unique constraint on pools

`mig:20251205142711:3-4` **drops both** unique constraints on `user_staking_pools`; the only
remaining unique is the primary key (`PLATFORM_RULES.md:678-683`). Unlimited duplicate pools per
(user, type, duration) are now legal. This also broke the `ON CONFLICT` fallback in the live
`process_staking_request` overload, which now raises rather than recovering
(`PLATFORM_RULES.md:830-836`).

I flag this because half the reward logic assumes one pool per key, and restoring the constraint is
a prerequisite for any idempotent credit path — including the ledger in §2. **This has to be fixed
before Group A, not after.** It also cannot be fixed without first resolving whatever duplicates
exist, which nobody has counted.

---

## 4. TOPOLOGY

### 4.1 The three environments

| | **v2 hosted** | **selfhost** | **PGlite hostless** |
|---|---|---|---|
| Where | Supabase cloud, project `lhkkfrpgbkjfcrodjslf` | Docker, 8 containers, `:55321` | In-process WASM Postgres |
| Entry | `ignitehex-v2/supabase/config.toml` | `ignitehex-selfhost/docker-compose.yml` | `ignitehex-v2/scripts/hostless-db.mjs` |
| Data | Real members, real balances | Migration replay, synthesised | Empty, built from migrations |
| Postgres | Supabase-managed | `supabase/postgres:15.8.1.060` | PGlite (WASM) |
| Auth / API | GoTrue + PostgREST | GoTrue `v2.174.0`, PostgREST `v12.2.12` | **none** |
| Edge functions | 94, deployed | `edge-runtime:v1.67.4`, mounts v2's functions read-only | **none** |
| Setup time | n/a | minutes, needs Docker | seconds, needs nothing |
| Can serve the app | yes | yes | **no** |

### 4.2 What each cannot do

**v2 hosted** cannot be experimented on. It carries the real €402M of booked balances and the open
containment window. It is also the only place production RLS actually exists — and this is a trap
that has already been documented: **the local rebuild's RLS is not production RLS.**
`PLATFORM_RULES.md:29-38` explains why. The recovered-schema generator emits blanket
`CREATE POLICY "recovered own <cmd>"` policies, and the production lockdown migration
`mig:20260509121934:11-13` drops policies **by name** — names the recovered policies do not have. So
the local database shows `user_staking_pools` as user-writable when production is not.
`rebuild-local.mjs` ends with a blanket `GRANT EXECUTE ON ALL FUNCTIONS … TO anon, authenticated`,
re-granting everything any migration revoked.

> **Never read an authorisation rule off a local database in this project.** Both audit documents
> source their RLS and grant statements from migrations only. Any test that asserts "this is denied"
> is currently meaningless locally, and this is the single most important operational fact in this
> review after §1.4.

To its credit, `rebuild-local.mjs:85-131` explicitly refuses the blanket grant for seven
reward-distribution functions and re-applies a denylist, because the blanket grant had previously
re-opened `distribute_enhanced_rewards`. That is a real, documented near-miss and the right instinct
— it needs to be generalised, not kept as seven special cases.

**selfhost** cannot be trusted as a security model, for reasons that are all fixable:

- `/functions/v1/`, `/storage/v1/` and `/realtime/v1/` carry **no `key-auth` plugin** at the gateway
  (`kong.generated.yml:35-49`) — only `/rest/v1/` and `/pg/` do. Upstream Supabase's reference
  config gates functions and storage too. Anything that can reach `localhost:55321` can invoke all
  94 edge functions without presenting a key. Those functions do their own JWT checks — but 27 of
  them have `verify_jwt = false` and six of those have no role check in code either.
- `main/index.ts:22` passes **the entire container environment into every function worker** —
  service-role key, the superuser `SUPABASE_DB_URL`, all vendor keys. No per-function scoping. One
  compromised function has full-database credentials.
- The `SERVICE_ROLE_KEY` in `.env:5` is a valid HS256 JWT **expiring 2031-08-17 — a five-year
  RLS-bypass credential** — stored in plaintext and additionally baked into `kong.generated.yml:12`.
  No rotation path exists in the tree.
- `/pg/` exposes postgres-meta connected as `supabase_admin` (`docker-compose.yml:166`) over the
  published port, with `hide_credentials: false` so the apikey is forwarded upstream.
- `DB_ENC_KEY: supabaserealtime` and `SECRET_KEY_BASE` (`docker-compose.yml:93,95`) are the
  well-known upstream sample values, unrotated.
- `main/index.ts:25-31` collapses **all** worker-creation failures to HTTP 404 "function not
  available". A boot crash, a syntax error and a typo'd name are indistinguishable. This will waste
  real debugging time.
- Only `db` has a healthcheck; Kong's `depends_on` (`docker-compose.yml:171`) is the short form, so
  Kong proxies while everything behind it is still booting.
- **A latent trap:** `init.generated/00-roles.sql` is stale — 17 minutes older than its source and
  missing the four `ALTER ROLE … PASSWORD` statements the source added
  (`init/00-roles.sql:26-29`) to align service credentials. Because `docker-entrypoint-initdb.d`
  runs **only when the data directory is empty**, and `db-data` is a persistent named volume, the
  regenerated file will never run again. Fixing role bootstrap requires `docker compose down -v` —
  destroying all data. Undocumented anywhere in the tree.
- `up.mjs` does not generate JWTs, does not wait for health, does not seed and **does not apply
  migrations**. It prints an instruction (`up.mjs:116-122`) whose password is `${'*'.repeat(8)}` —
  eight literal asterisks — so it cannot be copy-pasted.
- No `imgproxy`, no analytics, no Studio. `.env:6-7,12` define dashboard credentials and a Studio
  port for a service that does not exist.

**PGlite** cannot run the app, and its author says so plainly
(`ignitehex-v2/scripts/hostless-db.mjs:11-15`): no PostgREST, no GoTrue, no realtime. It also
substitutes **fake cryptography** — `crypt()` is `sha256(password || salt)` and `gen_salt()` is
8 random bytes hex-encoded (`:74-84`), with the comment *"it is NOT cryptography… Never point an
application at this build."* Heed that. `pg_cron` and `pg_net` are recorded and discarded.

What it *is*, and this is undersold: **it is a real Postgres that builds the whole schema in seconds
with no Docker, and `auth.uid()` reads the same session GUC PostgREST sets** (`:60-62`). A test can
`set local request.jwt.claim.sub = '<uuid>'` and exercise RLS for real. That is the entire basis of a
CI policy suite — and it is currently unused.

### 4.3 Which should be authoritative

**Development → the self-hosted stack, with the RLS caveat displayed prominently.** It is the only
environment that runs the whole product locally, and v3's `.env.local` already points at
`http://localhost:55321`. It must never be used to answer "is this permitted", and the fastest way to
enforce that is to fix the two generators — stop emitting blanket recovered policies, stop the
blanket `GRANT EXECUTE` — so that local authorisation converges on production instead of diverging.
Until that lands, treat every local permission result as unknown.

**CI → PGlite, as the schema and policy gate.** It needs no Docker, runs in seconds, and executes
real Postgres. Two jobs: (1) `hostless-db.mjs` must exit 0 — the schema builds; (2) the `tests/sql/`
suite runs against it, impersonating users via the GUC and asserting what RLS permits and denies.
The harness exists (`hex-ignite-nexus/scripts/run-sql-tests.mjs`) and **has no tests**. That is the
gap. Its RED-test convention — a test asserting behaviour the code does not yet have, whose failure
text *is* the finding — is exactly the right instrument for the 45 blocked actions: write the RED
test when you write the `TODO(server)`, and the roadmap measures itself.

Note one honest limitation: PGlite's `DATA_ONLY` classifier (`hostless-db.mjs:143-146`) is the same
"this is a production backfill, not a schema failure" filter that lets `rebuild-local.mjs` report 41
broken migrations as applied. In CI that is acceptable — you are gating the *schema* — but the count
must be printed and watched, not hidden.

**Production → v2 hosted, for now, and this is a decision to revisit rather than accept.** Hosted
Supabase is currently doing real work for you: managed backups, a managed Postgres, and — critically
— a `verify_jwt` gateway that the self-hosted Kong config does **not** replicate for functions. The
self-hosted stack in its present state is a *downgrade* in security posture, not an upgrade. It
becomes a credible production target only after the Kong routes are gated, the env injection is
scoped per function, and the service-role key gets a rotation path. Those are days of work, not
months, but they are not done.

**A gap nobody owns: there is no staging.** The v2 hosted project is production; local is
untrustworthy for authorisation; CI has no data. Every one of the seven routine families in §2 will
need to be tested against realistic data with production-shaped RLS before it touches real balances.
**Provision a staging Supabase project with production's schema and synthetic data before starting
Group A.** Without it, the ledger will be validated in an environment that has already been proven
to disagree with production about exactly the thing it is validating.

---

## 5. ROADMAP

Two tracks. **Track A must complete before the platform carries real money.** Track B improves it
and can run in parallel by different people.

### Phase 0 — Stop the bleeding · days · no dependencies

Blocking. Nothing else should start first.

| # | Action | Where |
|---|---|---|
| 0.1 | **Close the unauthenticated `process_staking_request` overload.** Repoint v3 to `(uuid, boolean, text)`; `REVOKE EXECUTE` on `(uuid, text, text)` from `PUBLIC`/`anon`/`authenticated`, or drop it. Correct the false comment. | `v3/src/domains/staking/hooks.ts:449-470`; new migration |
| 0.2 | **Confirm the 2026-08-18 forward fixes are deployed**, not merely committed. They revoke public EXECUTE on `distribute_enhanced_rewards` and add `assert_caller_owns` to the two debit functions. Verify against the live project — the audit records earlier hardening as *staged but unapplied*. | `v2/supabase/migrations/20260818120000`, `…120100` |
| 0.3 | **Keep the freezes in place** on `convert-wstr-to-fiat` and the fiat withdrawal rails until the ledger exists. This is what keeps €402M of paper liability from becoming cash. | `MASTER_AUDIT.md:33-38` |
| 0.4 | **Flip `verify_jwt = true`** on the 13 money-moving functions that have it disabled, and add role checks to the six that lack one. | `v2/supabase/config.toml` |
| 0.5 | **Gate `/functions/v1/` and `/storage/v1/` behind `key-auth`** in the self-hosted Kong config, matching upstream. | `selfhost/kong.yml:45-49` |

0.1 and 0.2 are the two that matter. The rest is hygiene that becomes harder later.

### Phase 1 — Make the work measurable · 1–2 weeks · after Phase 0

Nothing here changes behaviour. It makes every later phase verifiable, and it is the cheapest work
in this document.

| # | Action | Note |
|---|---|---|
| 1.1 | **Write v3's `package.json` dependencies** and commit a lockfile. Today `npm install` yields a tree that cannot build. | Blocks all CI |
| 1.2 | **Put v3 under version control.** It is not a git repository. | |
| 1.3 | **CI job 1: `hostless-db.mjs` exits 0**, printing applied / data-only / failed counts. Fail on any increase. | |
| 1.4 | **CI job 2: the `tests/sql/` suite.** Currently empty. Seed it with RED tests for the §2 routines and the §3.3 invariants. | Harness already exists |
| 1.5 | **Fix the two generators** so local RLS converges on production: no blanket recovered policies, no blanket `GRANT EXECUTE`. Generalise the seven-function denylist into a rule. | `gen-recovered-schema.mjs:402`, `rebuild-local.mjs:85-131` |
| 1.6 | **Provision staging** — production schema, synthetic data, production-shaped RLS. | Blocks Phase 3 |
| 1.7 | **Count the unknowns**: negative balances per table, duplicate pools per (user, type, duration), pools whose APY cannot be traced to a schedule. Each blocks a later phase and none has a number today. | |

### Phase 2 — Constrain the data model · 2–4 weeks · after 1.7

| # | Action | Depends on |
|---|---|---|
| 2.1 | **Restore the unique constraint on `user_staking_pools`.** Prerequisite for any idempotent credit. | 1.7 duplicate count |
| 2.2 | **`CHECK (>= 0)` on every balance column.** Note `fiat_wallets` needs a real `ALTER TABLE` — the existing declaration is a no-op inside `CREATE TABLE IF NOT EXISTS`. | 1.7 negative count |
| 2.3 | **`numeric(p,s)` on the ~20 columns the ledger will touch.** Not all 310. | 2.2 |
| 2.4 | **The `apy_schedule` table**, rates in integer basis points. Repoint every function; add the schedule-id column to pools; backfill what is determinable. | Business decision on rates |
| 2.5 | **The `asset_supply` table with enforced caps**, and a constraint trigger on minting paths. Enforcement switches on in 3.4. | 2.1 |

2.4 has a **non-engineering blocker**: someone must decide the rate schedule. Start that conversation
in Phase 0 — it has the longest lead time of anything here and it gates the investment product.

### Phase 3 — The ledger · 6–10 weeks · the critical path

| # | Action | Unblocks |
|---|---|---|
| 3.1 | **`post_entries(entries[])`** — balanced set, deterministic lock order, refuses a non-zero sum, one ledger row per leg, idempotency key, integer minor units from birth. | Everything below |
| 3.2 | **Balances become derived** from the ledger, reconciled to stored balances by a daily job that writes a finding on divergence. | Group G's findings table |
| 3.3 | **Group A's eleven routines** as thin callers of 3.1. | 11 controls |
| 3.4 | **Switch on cap enforcement** (2.5) now that every credit is a ledger entry. | §3.3 |
| 3.5 | **Group B's review routines** — decision and credit in one transaction. | 6 controls |

**After Phase 3 the platform can carry real money again.** Not before. Everything above this line is
either a precondition or a way of knowing whether the preconditions hold.

The commercial decision on the 963M excess CCOS should be made during Phase 3, because 3.4 forces it:
you cannot switch on a cap the current holdings breach by 16.3×. Reversible staged scripts exist at
`hex-ignite-nexus/docs/cleanup/`.

### Phase 4 — Restore the product · 8–12 weeks · after Phase 3

| # | Action | Unblocks |
|---|---|---|
| 4.1 | Group C — external settlement, one broadcaster that stores the hash the chain returned | 8 controls |
| 4.2 | Group D — issuance and provisioning, IBAN routines first | 10 controls |
| 4.3 | Group E — multi-row settlement; needs the per-listing payout-address model change | 3 controls |
| 4.4 | Group F — key custody | 2 controls |
| 4.5 | Group G — findings table, `freeze_wallet`, margin policy | 5 controls |

**Pull `freeze_wallet` (4.5) forward into Phase 3.** It is the containment primitive, it is small,
and an operator watching a live ledger without it has no lever.

### Track B — improves, does not block

Any of these can run in parallel from day one.

| Action | Where |
|---|---|
| Consolidate the six blocked-action primitives into one | `domains/*/shared.tsx`, `admin/components.tsx` |
| Move SAFE MODE from `localStorage` to a server-side operator flag | `domains/admin/lib/safeMode.ts` |
| Replace the `Math.random()` price feed with a real oracle | `v2/supabase/functions/str-price/index.ts:15-19` |
| Scope per-function env in the edge runtime; stop injecting the service-role key everywhere | `selfhost/main/index.ts:22` |
| Give the self-hosted service-role key a rotation path; drop the 5-year expiry | `selfhost/.env:5` |
| Stop masking function boot failures as 404 | `selfhost/main/index.ts:25-31` |
| Add healthchecks; use `service_healthy` in Kong's `depends_on` | `selfhost/docker-compose.yml:171` |
| Document the initdb-runs-once trap and fix `init.generated/00-roles.sql` | `selfhost/init/` |
| Move the service-role key out of `v3/.env.local` | |
| Migrate remaining money columns to `numeric(p,s)` domain by domain | ongoing |

---

## 6. Where I am uncertain

Stated plainly, with what would settle each.

1. **Whether the 2026-08-18 forward fixes are actually deployed.** They exist in the v2 tree. The
   audit records an earlier round of hardening as *staged but unapplied*, so the presence of a
   migration file is not evidence. **Needs:** `pg_proc` and `information_schema.role_routine_grants`
   read from the live project. This changes the severity of §1.4 and 0.2 substantially.
2. **The real production RLS.** Everything in both audit documents is sourced from migrations
   because the local database is untrustworthy on this point. Migrations tell you what was
   *attempted*. **Needs:** `pg_policies` and `pg_constraint` dumped from production. Until then, no
   statement about what is permitted is verified — including my §1.4 severity assessment.
3. **How many of the 41 skipped migrations touch money.** If any of the FK-deferred ones move
   balances or ownership, the local schema diverges from production in ways nobody has characterised.
   **Needs:** read those 41 files. Half a day.
4. **The counts in 1.7.** Negative balances, duplicate pools, untraceable APYs. Each blocks a Phase 2
   item and none has a number. **Needs:** three queries against staging or a read-only production
   session.
5. **Whether Realtime works in the self-hosted stack.** It is declared and routed but Realtime needs
   a provisioned tenant, and the stale `init.generated/00-roles.sql` may prevent
   `supabase_admin` from authenticating at all. **Needs:** a runtime test — five minutes, but it must
   be done against a running stack.
6. **Where the self-hosted JWTs came from.** `up.mjs` does not generate them; nothing in the tree
   does. If the generator is not under version control somewhere, the rotation path in Track B has no
   starting point.
7. **What the APY rates should be.** Not an engineering question, and the longest-lead-time blocker
   in this document. **Needs:** an owner decision.

---

## 7. Two places the sources of truth disagree

Recorded because in both cases the disagreement is more informative than either source.

**The brief versus the audit, on money representation.** The task described this as "the
float-vs-integer money representation (audit R2)". R2 is reward double-crediting
(`MASTER_AUDIT.md:150`); the float finding is B7/R8 (`:177`). And the database stores money as exact
`numeric` — zero `float8` columns across 723 migrations. The float problem is real but lives in four
edge functions and at the JS client boundary, not in the schema. If the roadmap had been written to
the brief's framing, it would have scheduled a 310-column type migration that fixes almost nothing
and skipped the transport layer where the loss actually occurs. See §3.1.

**v3's code comment versus the audit, on `process_staking_request`.** `domains/staking/hooks.ts:449-452`
states the RPC carries its authorisation check internally. `PLATFORM_RULES.md:818-828` documents that
the overload v3 calls has none. The comment is not careless — it is true of the *other* overload, the
one v2 called. Someone read the function name, confirmed the property on the version they found, and
wrote it down. Postgres then resolved a different function from the argument types. See §1.4.

**Where the documents themselves live** is worth recording too. The brief located
`PLATFORM_RULES.md` and `MASTER_AUDIT.md` in `ignitehex-v2/docs/`. Neither is there:
`PLATFORM_RULES.md` is in `ignitehex-v3/docs/`, and `MASTER_AUDIT.md` is in
`C:/Users/strho/hex-ignite-nexus/docs/` — a third tree, the working repo, which is also the tree
`PLATFORM_RULES.md` cites as `mig:` and `v1:`. Three trees hold authoritative artefacts and none of
them holds all three. That is a small thing that will cost someone an hour every time they onboard.
