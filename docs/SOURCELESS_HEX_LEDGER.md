# SourceLess HEX — the ledger, and what anchoring adds to it

Two migrations, two different jobs:

| | |
|---|---|
| `20260818160000_ledger_post_entries.sql` | the double-entry ledger. Internal correctness. |
| `20260819100000_ledger_anchor_sourceless_hex.sql` | the anchoring layer. External evidence. |

They are separate on purpose, and the separation is the most important design
decision in both files: **a balance never depends on a transaction confirming.**

---

## 1. What the ledger guarantees on its own

These hold with no chain, no network, and no worker running. They are properties
of the database, enforced by constraints and triggers rather than by discipline.

- **Value is conserved.** `post_entries()` refuses any batch whose signed
  amounts do not sum to zero per asset. A credit with no named account the value
  came out of is not a bug caught in review; it is a batch Postgres rejects.
- **Money is exact.** Amounts are `bigint` in minor units, with the scale fixed
  once per asset in `ledger_asset`. No IEEE-754 double touches a balance.
- **Postings are idempotent.** `ledger_journal.reference` is unique. Re-posting
  the same reference returns the original journal and changes nothing.
- **History is append-only.** `ledger_journal` and `ledger_entry` reject UPDATE
  and DELETE by trigger.
- **Only named platform accounts may go negative.** A member account cannot.
- **Members cannot post.** `post_entries` is a service-role primitive; member
  operations go through a wrapper that re-derives identity from the JWT.

That is a strong guarantee, and it is the *only* guarantee a balance rests on.

**What it does not give you:** every one of those assertions is made by the same
database that holds the money. A party who does not trust the operator has
nothing to check the operator against. The operator could, with table-owner
rights, disable the append-only triggers and rewrite an entry — as
`scripts/anchor-verify.sql` §2 does deliberately, to prove the next section
catches it.

---

## 2. What anchoring adds — and only this

Anchoring publishes a **SHA-256 of each journal batch** to a chain. That is all
it does, and the modesty is the point. Specifically it adds:

- **Third-party detectable alteration.** Once the hash of batch *B* is in a
  block, changing any entry of *B* — amount, account, ordering, count — changes
  the recomputed hash and no longer matches what was published. An auditor who
  never trusts this database can see the discrepancy.
- **A timestamp nobody here controls.** The block establishes that the batch
  existed in that exact form at that time.
- **A public commitment.** The operator cannot show one version of history to
  one party and a different version to another, because both hash-check against
  the same block.

**What anchoring does NOT add**, and must never be described as adding:

- It does **not** make balances more correct. The ledger was already exact.
- It does **not** move value. No token is transferred; a 32-byte hash is
  published. This is not a bridge and not a settlement layer.
- It does **not** hide anything or reveal anything. The hash is opaque; the
  entries stay in Postgres.
- It does **not** provide finality. Depth is recorded, never assumed — see §6.
- It does **not** anchor member balances, only batches. A balance is the sum of
  its batches; verifying a balance means verifying every batch that touched it.

---

## 3. The interface a chain has to satisfy

Everything chain-specific is a row in `ledger_anchor_chain`. No URL, chain id,
contract address, hash format or confirmation policy appears anywhere else.
**Going live is an UPDATE, not a rewrite.**

A worker loop is four calls:

```
1.  ledger_anchor_claim(worker, limit, lease_seconds)
        -> journal_id, content_hash, chain_id, rpc_url, anchor_target,
           contract_address, tx_hash_pattern, required_confirmations,
           attempt_no, lease_expires_at

2.  ...broadcast a transaction carrying content_hash...

3a. ledger_anchor_record_submission(journal_id, tx_hash, worker, submitted_at)
3b. ledger_anchor_record_failure(journal_id, error, worker)          [on error]

4.  ledger_anchor_record_confirmation(journal_id, confirmations,
                                      block_number, block_hash, worker)
                                                          [polled, repeatedly]
```

A chain qualifies if it can carry 32 bytes in a transaction and report how deep
that transaction is buried. Nothing else is assumed — not EVM, not a contract,
not an account model.

### Full signatures

| Function | Returns | Caller |
|---|---|---|
| `ledger_anchor_claim(text, int, int)` | `TABLE(journal_id uuid, reference text, content_hash text, hash_algorithm text, chain_id int, rpc_url text, anchor_target text, contract_address text, tx_hash_pattern text, required_confirmations int, attempt_no int, lease_expires_at timestamptz)` | `service_role` |
| `ledger_anchor_record_submission(uuid, text, text, timestamptz)` | `jsonb` | `service_role` |
| `ledger_anchor_record_confirmation(uuid, int, bigint, text, text)` | `jsonb` | `service_role` |
| `ledger_anchor_record_failure(uuid, text, text)` | `jsonb` | `service_role` |
| `ledger_anchor_reset(uuid, text)` | `jsonb` | `service_role` (operator) |
| `ledger_anchor_verify(uuid)` | `jsonb` | admin / auditor |
| `ledger_anchor_verify_range(timestamptz, timestamptz)` | `TABLE(journal_id, reference, posted_at, ledger_label, anchored_hash, recomputed_hash, matches, verdict, anchor_status, tx_hash, confirmations, required_confirmations)` | admin / auditor |
| `ledger_anchor_export(uuid)` | `jsonb` (canonical payload + sha256) | admin / auditor |
| `ledger_anchor_status()` | `jsonb` | admin / auditor |
| `public.ledger_anchor_queue` (view) | backlog, oldest first | admin (RLS) |

Internal, revoked from everyone including `service_role`:
`ledger_anchor_payload(uuid)`, `ledger_anchor_content_hash(uuid)`,
`ledger_anchor_enqueue()`, `ledger_anchor_guard_mutation()`,
`ledger_anchor_assert_service(text)`, `ledger_anchor_assert_reader(text)`.

---

## 4. The content hash, byte for byte

An auditor must be able to recompute this without Postgres, so the
serialisation is specified rather than incidental. `ledger_anchor_export()`
returns the exact payload alongside its hash.

```
SourceLess HEX/anchor-v1
journal:<journal uuid>
reference:<JSON-escaped string>
reason:<JSON-escaped string>
posted_at:<YYYY-MM-DDTHH:MM:SS.ffffffZ>
entries:<count>
<entry line>            -- repeated, ascending by entry uuid
```

with

```
entry line = entry_id|account_id|user_id|asset|bucket|amount|balance_after
```

- **LF** line separators, **UTF-8**, **no trailing newline**.
- `hash = sha256(payload_bytes)`, lowercase hex — `hash_algorithm` is recorded
  on the row as `sha256/sourceless-hex-anchor-v1`.

Four choices carry weight:

- **Timestamps are rendered `AT TIME ZONE 'UTC'` through `to_char`.** Casting a
  `timestamptz` to text would fold in the session `TimeZone` GUC and the same
  batch would hash differently for different readers. Proven in
  `anchor-verify.sql` §1(b), which hashes the same batch under `UTC` and under
  `Pacific/Kiritimati` (UTC+14) and gets an identical digest.
- **Free text is JSON-escaped.** A `|` or a newline inside a `reference` cannot
  be mistaken for a field separator.
- **Entries are ordered by their UUID**, which Postgres compares as 16 raw
  bytes. No collation is involved, so the order is identical on every
  installation and reproduces as a lexicographic sort of the lowercase
  canonical hex form.
- **`user_id`, `asset` and `bucket` are pulled from `ledger_account`** as well
  as `account_id`, so repointing an account row is as detectable as editing an
  amount.

Example payload from a real run:

```
SourceLess HEX/anchor-v1
journal:9fcc1ce1-dc59-47e4-afeb-c6f71b883fc6
reference:"anchorverify:042135011795:A"
reason:"SourceLess HEX anchor fixture batch A"
posted_at:2026-08-19T04:21:35.013960Z
entries:2
b3bdef56-...-888ea7c7731e|8b93d1a0-...|b82ceeae-...|STR|liquid|100000000|1318500000000
ba5f0651-...-0556180def5a|2a92cfbc-...|00000000-0000-0000-0000-00000000e002|STR|liquid|-100000000|-100000000
```

---

## 5. Where the hash is stamped, and why that matters

`ledger_journal` carries a **`DEFERRABLE INITIALLY DEFERRED` constraint
trigger** (`ledger_journal_anchor_enqueue`). It fires at COMMIT, by which time
every `ledger_entry` for the batch exists, so the hash covers all of them and is
stamped **inside the same transaction that created the batch**. There is no
window in which a batch exists un-hashed.

The trigger body contains **no `RAISE` and no lookup that can fail**. A missing
or truncated chain registry leaves `chain_id` NULL rather than failing the
posting. This is where rule 1 — *a balance never depends on anchoring* — is
enforced, at the one place where anchoring could otherwise reach back into the
money path.

And the queue does not trust the trigger. `ledger_anchor_queue` is a `LEFT JOIN`
from `ledger_journal`, so a batch with no anchor row at all — trigger dropped,
migration half-applied — appears with `missing_anchor_row = true` rather than
vanishing. `ledger_anchor_claim` creates the row on demand.

---

## 6. The rules the anchoring layer refuses to break

### A transaction hash is never fabricated

v2 generated them with `` `0x${Math.random().toString(16)}` `` and stored the
result as settled — v3's `src/domains/marketplace/hooks.ts:846` records the
defect. Here:

- `tx_hash` is `NULL` until a receipt exists, and **no code path in the
  migration generates one**;
- it is validated against `ledger_anchor_chain.tx_hash_pattern` before storage,
  so a `Math.random()` artefact is rejected outright;
- it is **write-once**, guarded by trigger;
- `CHECK` constraints make `status IN ('submitted','confirmed') AND tx_hash IS
  NULL` an *unrepresentable* state, as are `confirmed` without `confirmed_at`,
  and `failed` without `last_error`;
- a partial unique index on `(chain_id, lower(tx_hash))` stops one receipt
  anchoring two batches.

### Idempotent, resumable, never double-submitting

- **Same hash twice → one anchor.** The second call returns
  `{"recorded": false, "idempotent": true}` and changes nothing.
- **A different hash for the same batch is refused, not overwritten.** Two
  broadcasts for one batch is an incident; the first receipt is kept and the
  second is written to `ledger_anchor_attempt` as a `conflict`, because
  silently keeping either would destroy the evidence.
- **Leases, not locks.** `ledger_anchor_claim` uses `FOR UPDATE SKIP LOCKED`, so
  concurrent workers take disjoint sets. A worker that dies leaves a lease that
  lapses; resumption is the ordinary path, not a recovery procedure.
- **A batch that already has a receipt never re-enters the queue on its own** —
  not even after `record_failure`. Re-broadcasting over a transaction that may
  still be in a mempool is the one thing a worker must never decide alone. The
  only way back is `ledger_anchor_reset(journal_id, reason)`, which a human
  calls and which writes the superseded hash to the attempt log *before* it
  clears it.

### Reorgs are real

`confirmations` is an observed depth recorded on every poll, and it is
**allowed to go down**. Crossing `required_confirmations` upward marks the
anchor confirmed; falling back below it returns the anchor to `submitted`,
increments `reorg_count` and records the reason. Nothing treats one confirmation
as final.

### An unreachable chain is an error state, not a stub

There is no mock in the migration. When the default chain is disabled,
`ledger_anchor_claim` **raises** (SQLSTATE `55000`) and names the recorded
reason. It deliberately does **not** return an empty set: "no work" and
"anchoring is broken" are different facts, and a worker that cannot tell them
apart logs *nothing to do* forever. `ledger_anchor_status()` returns
`healthy: false` with an `alert` string, the queue depth and the age of the
oldest unanchored batch.

The only test double is `scripts/anchor-verify.sql`, which is a test script and
named as one.

### Keys never reach the browser

Every write function is `service_role`-only by GRANT **and** re-checks the
caller in its body, because `scripts/rebuild-local.mjs` has swept revoked
functions back open before. The submitting key lives with the worker; no part
of this design puts a signer in a browser.

---

## 7. Exactly what is needed from the SourceLess chain to go live

**As of 2026-08-19 the chain is unreachable and nothing has been tested against
it.** Independently probed:

```
https://rpc.sourceless.net           http=000  curl exit 6 (could not resolve host)
https://explorer.sourceless.net      http=000  curl exit 6 (could not resolve host)
https://sourceless.net               http=301  → 99.83.190.102, 198.202.211.1

nslookup rpc.sourceless.net          NXDOMAIN
nslookup explorer.sourceless.net     NXDOMAIN
```

The chain row exists, carries the values transcribed from `src/lib/wagmi.ts`,
and is `enabled = false` with that probe result on record.

### The blocking list

| # | Needed | Why it blocks | Where it lands |
|---|---|---|---|
| 1 | **A resolving RPC endpoint** and its protocol (JSON-RPC? something else?) | Nothing can be broadcast or polled | `ledger_anchor_chain.rpc_url` |
| 2 | **Confirmation that the chain id really is 2025** | Replay protection; a wrong id makes every signature invalid or replayable | `ledger_anchor_chain.chain_id` |
| 3 | **The transaction shape for carrying 32 bytes** — a self-send with the hash as calldata, or a call to an anchoring contract | `anchor_target` is `NULL`, which is why the chain cannot be enabled | `anchor_target`, `contract_address` |
| 4 | **A funded submitter account** with enough STR for gas, plus the fee model (fixed? EIP-1559? gas price oracle?) and who owns and rotates the key | No account, no anchoring; and the key custody decision is not ours to make silently | worker secret store, never the database |
| 5 | **The real receipt-hash format** | `tx_hash_pattern` defaults to `^0x[0-9a-f]{64}$` — the EVM shape, inferred from `wagmi.ts`, not confirmed | `ledger_anchor_chain.tx_hash_pattern` |
| 6 | **The chain's finality rule** — block time, reorg depth actually observed, whether there is deterministic finality | `required_confirmations = 12` is the **Ethereum convention used as a placeholder**, not a statement about SourceLess | `ledger_anchor_chain.required_confirmations` |
| 7 | **A reachable explorer**, or an admission that there is none | Auditors need a URL to check the receipt against; `explorer_url` currently NXDOMAINs | `ledger_anchor_chain.explorer_url` |
| 8 | **The chain repository / spec** | Items 3, 5 and 6 cannot be answered without it | — |

Once those are answered, going live is:

```sql
UPDATE public.ledger_anchor_chain
   SET rpc_url                = '<real endpoint>',
       explorer_url           = '<real explorer>',
       anchor_target          = 'calldata',        -- or 'contract'
       contract_address       = '<if contract>',
       tx_hash_pattern        = '<confirmed format>',
       required_confirmations = <the chain's stated rule>,
       enabled                = true,
       disabled_reason        = NULL,
       last_probe_at = now(), last_probe_ok = true, last_probe_error = NULL
 WHERE chain_id = 2025;
```

The `enabled` gate has a `CHECK` behind it: a row cannot be enabled without an
`rpc_url` and an `anchor_target`, so "enabled with nowhere to send it" is not a
representable configuration.

---

## 8. What is deliberately NOT done yet

Each of these is an omission with a reason, not an oversight.

- **No worker.** The four-call interface exists and is tested; the process that
  broadcasts is not written, because it cannot be tested against anything. It
  needs at minimum: a service-role connection, the submitter key from a secret
  store, retry with backoff on `record_failure`, and a separate confirmation
  poller.
- **No mock chain, anywhere in the migration.** A mock that pretends to anchor
  produces exactly the records v2 produced. The absence is the design.
- **No batching of batches.** Every journal gets its own transaction and its own
  gas. A Merkle root over many batches with per-batch inclusion proofs is the
  obvious optimisation and would change the payload format, so it belongs behind
  `anchor-v2` rather than bolted on now.
- **No automatic reachability probing.** `last_probe_at` / `last_probe_ok` /
  `last_probe_error` are recorded by whoever probes; the database does not make
  outbound calls. Probing lives with the worker.
- **No automatic disabling on repeated failure.** `attempts` grows and
  `ledger_anchor_status()` surfaces `retried_over_3`; nothing silently gives up,
  because a queue that quietly stops is the failure mode this design is built
  against.
- **No verification against the chain.** `ledger_anchor_verify` compares the
  recomputed hash to what this database recorded as anchored. It does **not**
  fetch the transaction and confirm the same 32 bytes are in the block — that
  needs a reachable RPC. Until then the verdicts are honestly named
  `verified_locally_*`, and only `verified_on_chain` implies depth was observed.
- **No v3 frontend surface.** No component reads any of this. Admin UI is a
  separate decision.
- **No key management.** The migration never sees a key and has nowhere to put
  one. Custody, rotation and HSM-or-not are open.

---

## 9. Verification actually run

`node scripts/rebuild-local.mjs --container ignitehex-db-1` — full replay from
an empty schema:

```
  total          727
  applied        687
  data-only skip 40   (backfills of production rows)
  FAILED         0   (0.0%)
```

`docker exec -i ignitehex-db-1 psql … -f scripts/anchor-verify.sql` — exit 0,
16 PASS assertions, covering:

| § | Proved |
|---|---|
| 0 | The DEFERRED trigger fires at COMMIT: 3 batches, 3 anchor rows, hash stamped, `tx_hash IS NULL`, label `SourceLess HEX` |
| 1 | Same batch hashes identically twice, and identically again under `TimeZone = Pacific/Kiritimati`; matches the stored value; distinct batches hash distinctly |
| 2 | Disabling the append-only trigger and adding 1 to one leg changes the hash (`fc84d8cb…` → `6da96c4a…`); `verify` returns `TAMPERED`; the sweep sorts it to the top; rollback restores the match; the append-only trigger refuses the UPDATE in the first place |
| 3 | Queue in `posted_at` order; claim refuses with SQLSTATE `55000` while the chain is disabled; two workers take disjoint sets; a third gets 0 rows *without* an error once the chain is up; an expired lease returns work to the queue; a batch with a receipt is skipped |
| 4 | A `Math.random()`-shaped hash is refused; an empty hash is refused; the same receipt twice is one anchor; a conflicting second receipt is refused and logged; one receipt cannot anchor two batches |
| 5 | Depth 3/12 → `submitted`; 14/12 → `confirmed`; then depth 2 → back to `submitted`, `reorg_count = 1`, reason recorded; a batch with no receipt has no depth to confirm |
| 6 | Failure without a receipt requeues; failure *with* a receipt does not; `tx_hash`, `content_hash` and row deletion are all refused; `reset` supersedes and preserves the old hash |
| 7 | anon/authenticated have EXECUTE on **no** write function; anon reads 0 rows and a non-admin member reads 0 rows through RLS even after the rebuild's blanket `GRANT ALL`; all 5 write functions still refuse a browser session after the grant is handed back; a member is refused the read path and an admin is granted it |
| 8–9 | `status()` reports `healthy: false` with the queue depth and backlog age; `export()` returns the canonical payload and its digest |

### One real bug the verification caught

The first version of the read gate on `verify` / `verify_range` / `export` /
`status` was written as

```sql
IF NOT (public.is_admin(auth.uid())
        OR ... = 'service_role'
        OR session_user IN ('postgres','supabase_admin','service_role'))
```

`session_user` is `postgres` inside psql and in any pooled connection whatever
role the request carries, so that `OR` waved **every** browser request straight
through. It is now `ledger_anchor_assert_reader()`, which treats a session as a
server session only when the JWT role **and** the login role both say so — the
same shape `post_entries` uses. The failing test is what surfaced it.
