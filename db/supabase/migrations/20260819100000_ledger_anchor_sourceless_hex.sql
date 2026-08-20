-- =====================================================================
-- SourceLess HEX -- anchoring the double-entry ledger to a chain.
--
-- WHY THIS EXISTS
--
--   20260818160000 built the ledger: post_entries() refuses any batch whose
--   signed amounts do not sum to zero per asset, and both ledger_journal and
--   ledger_entry are append-only by trigger. That is a strong internal
--   guarantee and it is the ONLY guarantee that a balance depends on.
--
--   What it does not give you is external evidence. Everything the ledger
--   asserts is asserted by the same database that holds the money, so a party
--   who does not trust the operator has nothing to check the operator against.
--   Anchoring closes that gap and nothing else: it publishes a hash of each
--   batch to a chain, so that "these entries are the ones that were posted at
--   that time" becomes a claim a third party can test.
--
-- THE RULES THIS FILE IS BUILT AROUND
--
--   1. OFF-CHAIN FIRST, ANCHOR SECOND. A balance never depends on a
--      transaction confirming. post_entries commits, and the balance is real
--      the moment it commits. The anchor row is created by a DEFERRED
--      constraint trigger, so it cannot fail the posting on any normal path,
--      and the queue is a LEFT JOIN from ledger_journal so that a batch with
--      no anchor row at all still shows up as work rather than disappearing.
--
--   2. NEVER FABRICATE A TRANSACTION HASH. v2 generated them with
--      `0x${Math.random().toString(16)}` and stored the result as settled --
--      v3's marketplace/hooks.ts:846 records the defect in as many words. Here
--      tx_hash is NULL until a receipt exists, it is write-once, it is checked
--      against the chain's declared hash format before it is accepted, and the
--      table CHECKs make `status = 'confirmed' AND tx_hash IS NULL` an
--      unrepresentable state. There is no code path in this file that
--      generates a hash.
--
--   3. IDEMPOTENT AND RESUMABLE. A worker that dies mid-flight leaves a lease
--      that expires; nothing is lost and nothing is submitted twice. Recording
--      the same tx hash twice is one anchor. A row that already carries a tx
--      hash NEVER re-enters the queue on its own -- only a deliberate operator
--      reset can supersede it, and the superseded hash is kept.
--
--   4. REORGS ARE REAL. Confirmation depth is a recorded, mutable number, not
--      an assumption. A confirmed anchor whose depth falls back below the
--      policy returns to 'submitted' and its reorg_count increments. Nothing
--      here treats one confirmation as final.
--
--   5. AN UNREACHABLE CHAIN IS AN ERROR STATE, NOT A STUB. As of this
--      migration, rpc.sourceless.net and explorer.sourceless.net do not
--      resolve. The chain row is therefore present but DISABLED, with the
--      reason recorded. ledger_anchor_claim() REFUSES to hand out work and
--      says why. ledger_anchor_status() reports the backlog and its age.
--      Nothing in this file pretends to anchor, and no test double lives here.
--
-- THE INTERFACE A CHAIN MUST SATISFY (all four calls, nothing else)
--
--   ledger_anchor_claim(worker, limit, lease_seconds)
--       -> (journal_id, content_hash, chain_id, rpc_url, anchor_target,
--           contract_address, required_confirmations, ...)
--   ledger_anchor_record_submission(journal_id, tx_hash, worker)
--   ledger_anchor_record_confirmation(journal_id, confirmations, block, ...)
--   ledger_anchor_record_failure(journal_id, error, worker)
--
--   A chain qualifies if it can carry 32 bytes in a transaction and can tell
--   you how deep that transaction is buried. Everything chain-specific -- URL,
--   chain id, hash format, contract address, confirmation policy -- is a row
--   in ledger_anchor_chain. Going live is an UPDATE, not a rewrite.
--
-- SECTIONS
--   1. The chain registry (configuration, not code)
--   2. The anchor table and its attempt log
--   3. Canonical content hash
--   4. Enqueue (deferred trigger) + backfill
--   5. The queue and the claim
--   6. Recording submission, confirmation, failure, reset
--   7. Verification -- the auditor's entry point
--   8. Status / health
--   9. Privileges
--  10. Fail the migration rather than ship a hole
-- =====================================================================


-- =====================================================================
-- 1. THE CHAIN REGISTRY
--
-- One row per chain the ledger may anchor to. This is the whole of the
-- chain-specific surface: no URL, chain id or hash format appears anywhere
-- else in this file.
--
-- `enabled` is the gate, and it is false until somebody has actually reached
-- the endpoints. An enabled row must carry an rpc_url and an anchor_target,
-- because "enabled with nowhere to send it" is the silent-stub failure this
-- design exists to prevent.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.ledger_anchor_chain (
  chain_id               int  PRIMARY KEY,
  name                   text NOT NULL,
  native_symbol          text NOT NULL,
  native_decimals        int  NOT NULL CHECK (native_decimals BETWEEN 0 AND 36),
  rpc_url                text,
  explorer_url           text,

  -- How a batch hash is put on chain. 'calldata' = a 0-value self-send whose
  -- input data is the 32-byte hash; 'contract' = a call to contract_address.
  -- Which one SourceLess supports is one of the open questions in
  -- docs/SOURCELESS_HEX_LEDGER.md.
  anchor_target          text CHECK (anchor_target IN ('calldata','contract')),
  contract_address       text,

  -- The shape a receipt hash must have before this database will store it.
  -- The regex is the anti-fabrication check with teeth: a placeholder, a
  -- truncated string or a Math.random() artefact does not match a 32-byte
  -- lowercase hex hash, and record_submission rejects it.
  tx_hash_pattern        text NOT NULL DEFAULT '^0x[0-9a-f]{64}$',

  -- PROVISIONAL until SourceLess states its finality rule. 12 is the Ethereum
  -- convention and a placeholder, not a fact about this chain.
  required_confirmations int  NOT NULL DEFAULT 12 CHECK (required_confirmations >= 1),

  enabled                boolean NOT NULL DEFAULT false,
  disabled_reason        text,
  is_default             boolean NOT NULL DEFAULT false,

  -- What the last reachability probe actually saw. Written by an operator or a
  -- worker; never guessed.
  last_probe_at          timestamptz,
  last_probe_ok          boolean,
  last_probe_error       text,

  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ledger_anchor_chain_enabled_is_configured
    CHECK (NOT enabled OR (rpc_url IS NOT NULL AND btrim(rpc_url) <> ''
                           AND anchor_target IS NOT NULL)),
  CONSTRAINT ledger_anchor_chain_disabled_says_why
    CHECK (enabled OR disabled_reason IS NOT NULL),
  CONSTRAINT ledger_anchor_chain_contract_has_address
    CHECK (anchor_target IS DISTINCT FROM 'contract' OR contract_address IS NOT NULL)
);

-- Exactly one default target.
CREATE UNIQUE INDEX IF NOT EXISTS ledger_anchor_chain_one_default
  ON public.ledger_anchor_chain (is_default) WHERE is_default;

COMMENT ON TABLE public.ledger_anchor_chain IS
  'SourceLess HEX: the anchoring targets. Going live is an UPDATE here, not a code change.';

-- The SourceLess row, transcribed from src/lib/wagmi.ts (chain 2025, native
-- STR, 18 decimals) and DISABLED, because both endpoints were probed on
-- 2026-08-19 and neither resolved.
INSERT INTO public.ledger_anchor_chain
  (chain_id, name, native_symbol, native_decimals, rpc_url, explorer_url,
   anchor_target, contract_address, required_confirmations,
   enabled, disabled_reason, is_default,
   last_probe_at, last_probe_ok, last_probe_error)
VALUES
  (2025, 'SourceLess', 'STR', 18,
   'https://rpc.sourceless.net', 'https://explorer.sourceless.net',
   NULL, NULL, 12,
   false,
   'Not live. Probed 2026-08-19: rpc.sourceless.net and explorer.sourceless.net '
   || 'both return NXDOMAIN (curl exit 6, "could not resolve host", HTTP 000). '
   || 'Only the apex sourceless.net resolves (99.83.190.102, 198.202.211.1) and '
   || 'it answers 301. '
   || 'The chain repository has not been provided, so the transaction shape '
   || '(anchor_target), any anchoring contract address, the real tx-hash format '
   || 'and the chain''s finality rule are all unknown. required_confirmations=12 '
   || 'is the Ethereum convention used as a placeholder, NOT a statement about '
   || 'SourceLess. Set anchor_target, confirm tx_hash_pattern, replace '
   || 'required_confirmations with the chain''s stated rule, fund a submitter '
   || 'account with STR for gas, then set enabled = true.',
   true,
   now(), false,
   'curl exit 6: could not resolve host (NXDOMAIN on both subdomains)')
ON CONFLICT (chain_id) DO NOTHING;


-- =====================================================================
-- 2. THE ANCHOR TABLE AND ITS ATTEMPT LOG
--
-- One anchor row per journal batch. The row is current state; every state
-- change also writes an append-only attempt row, so the history of a
-- submission survives even when the state moves on.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.ledger_anchor (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- The label this ledger anchors under. Fixed by trigger once written.
  ledger_label           text NOT NULL DEFAULT 'SourceLess HEX',

  journal_id             uuid NOT NULL
                           REFERENCES public.ledger_journal(id) ON DELETE RESTRICT,

  -- sha256 over the canonical payload (section 3), hex, lowercase. Fixed when
  -- the batch is enqueued and immutable thereafter -- a content hash you can
  -- rewrite verifies nothing.
  content_hash           text NOT NULL CHECK (content_hash ~ '^[0-9a-f]{64}$'),
  hash_algorithm         text NOT NULL DEFAULT 'sha256/sourceless-hex-anchor-v1',

  -- NULL until the batch is routed to a chain. Not invented, same as tx_hash.
  chain_id               int REFERENCES public.ledger_anchor_chain(chain_id),

  -- NULL until a receipt exists. THERE IS NO CODE PATH IN THIS FILE THAT
  -- GENERATES THIS VALUE. Write-once; only ledger_anchor_reset may supersede
  -- it, and it records the superseded hash before it does.
  tx_hash                text CHECK (tx_hash IS NULL OR btrim(tx_hash) <> ''),
  block_number           bigint CHECK (block_number IS NULL OR block_number >= 0),
  block_hash             text CHECK (block_hash IS NULL OR btrim(block_hash) <> ''),

  status                 text NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending','submitted','confirmed','failed')),

  -- Depth, not finality. Recorded every poll; may go DOWN on a reorg.
  confirmations          int NOT NULL DEFAULT 0 CHECK (confirmations >= 0),
  required_confirmations int CHECK (required_confirmations IS NULL OR required_confirmations >= 1),
  reorg_count            int NOT NULL DEFAULT 0 CHECK (reorg_count >= 0),

  attempts               int NOT NULL DEFAULT 0 CHECK (attempts >= 0),

  enqueued_at            timestamptz NOT NULL DEFAULT now(),
  submitted_at           timestamptz,
  confirmed_at           timestamptz,
  failed_at              timestamptz,
  last_error             text,

  -- The lease. A worker holds a batch for lease_expires_at; if it dies, the
  -- lease lapses and the batch is claimable again. This is what makes the
  -- pipeline resumable without a gap.
  claimed_by             text,
  claimed_at             timestamptz,
  lease_expires_at       timestamptz,

  updated_at             timestamptz NOT NULL DEFAULT now(),

  -- One anchor per batch, named so ON CONFLICT can target it unambiguously
  -- from inside a function whose OUT parameter is also called journal_id.
  CONSTRAINT ledger_anchor_journal_key UNIQUE (journal_id),

  -- Unrepresentable states. Each of these is a v2 defect made impossible.
  CONSTRAINT ledger_anchor_submitted_has_receipt
    CHECK (status <> 'submitted' OR tx_hash IS NOT NULL),
  CONSTRAINT ledger_anchor_confirmed_has_receipt
    CHECK (status <> 'confirmed' OR (tx_hash IS NOT NULL
                                     AND confirmed_at IS NOT NULL
                                     AND confirmations >= 1
                                     AND required_confirmations IS NOT NULL)),
  CONSTRAINT ledger_anchor_pending_has_no_receipt
    CHECK (status <> 'pending' OR tx_hash IS NULL),
  CONSTRAINT ledger_anchor_failure_says_why
    CHECK (status <> 'failed' OR (last_error IS NOT NULL AND failed_at IS NOT NULL)),
  CONSTRAINT ledger_anchor_confirmed_at_needs_receipt
    CHECK (confirmed_at IS NULL OR tx_hash IS NOT NULL),
  CONSTRAINT ledger_anchor_submitted_at_needs_receipt
    CHECK (submitted_at IS NULL OR tx_hash IS NOT NULL)
);

-- The same transaction can anchor at most one batch. Catches a worker that
-- reuses a receipt across batches, which would make one anchor look like many.
CREATE UNIQUE INDEX IF NOT EXISTS ledger_anchor_tx_unique
  ON public.ledger_anchor (chain_id, lower(tx_hash)) WHERE tx_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS ledger_anchor_open_idx
  ON public.ledger_anchor (status, enqueued_at) WHERE status IN ('pending','failed');
CREATE INDEX IF NOT EXISTS ledger_anchor_inflight_idx
  ON public.ledger_anchor (status, submitted_at) WHERE status = 'submitted';

COMMENT ON TABLE public.ledger_anchor IS
  'SourceLess HEX: one row per ledger_journal batch, recording the batch content hash and the chain receipt for it. tx_hash is NULL until a receipt exists and is never generated.';
COMMENT ON COLUMN public.ledger_anchor.tx_hash IS
  'The chain receipt. NULL means no receipt yet -- it does NOT mean pending-but-probably-fine, and it is never filled in with a placeholder.';
COMMENT ON COLUMN public.ledger_anchor.confirmations IS
  'Observed depth at the last poll. May decrease: reorgs are real and this column is allowed to record one.';

-- The history. Append-only: an attempt log a later UPDATE can rewrite is not a
-- log. This is where a superseded tx hash goes when an operator resets a row,
-- and where a conflicting second hash goes when a worker submits twice.
CREATE TABLE IF NOT EXISTS public.ledger_anchor_attempt (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  anchor_id     uuid NOT NULL REFERENCES public.ledger_anchor(id) ON DELETE RESTRICT,
  journal_id    uuid NOT NULL,
  attempt_no    int  NOT NULL,
  outcome       text NOT NULL CHECK (outcome IN
                  ('claimed','submitted','duplicate','conflict','confirmed',
                   'reorg','failed','reset')),
  tx_hash       text,
  confirmations int,
  chain_id      int,
  worker        text,
  detail        text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ledger_anchor_attempt_journal_idx
  ON public.ledger_anchor_attempt (journal_id, created_at DESC);

DROP TRIGGER IF EXISTS ledger_anchor_attempt_immutable ON public.ledger_anchor_attempt;
CREATE TRIGGER ledger_anchor_attempt_immutable
  BEFORE UPDATE OR DELETE ON public.ledger_anchor_attempt
  FOR EACH ROW EXECUTE FUNCTION public.ledger_reject_mutation();

-- What may change on an anchor row, and what may not.
--
-- tx_hash is write-once. The single exception is ledger_anchor_reset, which
-- announces itself with a transaction-local marker after it has already
-- written the superseded hash into the attempt log -- the same delegation
-- pattern post_entries uses for its wrappers.
CREATE OR REPLACE FUNCTION public.ledger_anchor_guard_mutation()
RETURNS trigger LANGUAGE plpgsql AS $guard$
DECLARE
  v_reset boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'ledger_anchor is append-and-amend, never delete: an anchor row is the evidence that a batch was published'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.journal_id IS DISTINCT FROM OLD.journal_id THEN
    RAISE EXCEPTION 'ledger_anchor.journal_id cannot be repointed: the anchor would then attest to a batch it never hashed'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.content_hash IS DISTINCT FROM OLD.content_hash THEN
    RAISE EXCEPTION 'ledger_anchor.content_hash is fixed when the batch is enqueued; a hash you can rewrite verifies nothing'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.ledger_label IS DISTINCT FROM OLD.ledger_label THEN
    RAISE EXCEPTION 'ledger_anchor.ledger_label is fixed at %', OLD.ledger_label
      USING ERRCODE = '42501';
  END IF;

  IF OLD.tx_hash IS NOT NULL AND NEW.tx_hash IS DISTINCT FROM OLD.tx_hash THEN
    v_reset := coalesce(current_setting('ignitehex.anchor_reset', true), 'off') = 'on';
    IF NOT v_reset THEN
      RAISE EXCEPTION 'ledger_anchor.tx_hash is write-once (currently %). Use ledger_anchor_reset() to supersede a dead transaction; it records the old hash first.',
        OLD.tx_hash USING ERRCODE = '42501';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END
$guard$;

DROP TRIGGER IF EXISTS ledger_anchor_guard ON public.ledger_anchor;
CREATE TRIGGER ledger_anchor_guard
  BEFORE UPDATE OR DELETE ON public.ledger_anchor
  FOR EACH ROW EXECUTE FUNCTION public.ledger_anchor_guard_mutation();


-- =====================================================================
-- 3. THE CANONICAL CONTENT HASH
--
-- The point of a content hash is that somebody who does not have this database
-- can compute it. So the serialisation is spelled out, byte for byte, and it
-- avoids every construct whose result depends on session state:
--
--   * timestamps are rendered AT TIME ZONE 'UTC' through to_char, so the
--     session TimeZone GUC cannot change the bytes;
--   * free text (reference, reason) is JSON-escaped, so a '|' or a newline
--     inside a reference cannot be confused with a field separator;
--   * entries are ordered by their uuid, which Postgres compares as 16 raw
--     bytes -- no collation is involved, so the order is the same on every
--     installation and reproduces as a lexicographic sort of the lowercase
--     canonical hex form;
--   * amounts are bigint, rendered exactly; no float ever touches this.
--
-- Layout (LF between lines, no trailing newline):
--
--   SourceLess HEX/anchor-v1
--   journal:<journal uuid>
--   reference:<JSON string>
--   reason:<JSON string>
--   posted_at:<YYYY-MM-DDTHH:MM:SS.ffffffZ>
--   entries:<count>
--   <entry line>            -- repeated, ascending by entry uuid
--
-- entry line = entry_id|account_id|user_id|asset|bucket|amount|balance_after
--
-- The account's (user_id, asset, bucket) is included as well as its id, so
-- repointing an account row is as detectable as editing an amount.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ledger_anchor_payload(p_journal_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $payload$
  SELECT concat_ws(E'\n',
           'SourceLess HEX/anchor-v1',
           'journal:'   || j.id::text,
           'reference:' || to_jsonb(j.reference)::text,
           'reason:'    || to_jsonb(j.reason)::text,
           'posted_at:' || to_char(j.posted_at AT TIME ZONE 'UTC',
                                   'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
           'entries:'   || (SELECT count(*) FROM public.ledger_entry e
                             WHERE e.journal_id = j.id)::text,
           coalesce(
             (SELECT string_agg(
                       concat_ws('|', e.id::text, e.account_id::text, a.user_id::text,
                                 e.asset, a.bucket, e.amount::text, e.balance_after::text),
                       E'\n' ORDER BY e.id)
                FROM public.ledger_entry e
                JOIN public.ledger_account a ON a.id = e.account_id
               WHERE e.journal_id = j.id),
             ''))
    FROM public.ledger_journal j
   WHERE j.id = p_journal_id
$payload$;

CREATE OR REPLACE FUNCTION public.ledger_anchor_content_hash(p_journal_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $chash$
  SELECT encode(sha256(convert_to(public.ledger_anchor_payload(p_journal_id), 'UTF8')), 'hex')
$chash$;

COMMENT ON FUNCTION public.ledger_anchor_content_hash(uuid) IS
  'SourceLess HEX: sha256 of the canonical batch payload, hex. Deterministic and reproducible outside this database -- see docs/SOURCELESS_HEX_LEDGER.md for the byte layout.';


-- =====================================================================
-- 4. ENQUEUE
--
-- A DEFERRED constraint trigger, so it fires at COMMIT, by which time every
-- ledger_entry for the batch exists and the hash covers all of them. Firing at
-- INSERT time would hash an empty batch.
--
-- The body has no RAISE in it and no lookup that can fail: a missing or
-- truncated chain registry leaves chain_id NULL rather than failing the
-- posting. Rule 1 -- a balance never depends on anchoring -- is enforced here,
-- in the one place where anchoring could otherwise reach back into the money
-- path.
--
-- The queue in section 5 does NOT trust this trigger. It is a LEFT JOIN from
-- ledger_journal, so a batch with no anchor row -- trigger dropped, migration
-- half-applied, whatever -- still appears as work.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ledger_anchor_enqueue()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $enq$
DECLARE
  v_chain int;
  v_conf  int;
BEGIN
  SELECT chain_id, required_confirmations INTO v_chain, v_conf
    FROM public.ledger_anchor_chain WHERE is_default;

  INSERT INTO public.ledger_anchor
    (journal_id, content_hash, chain_id, required_confirmations, status)
  VALUES
    (NEW.id, public.ledger_anchor_content_hash(NEW.id), v_chain, v_conf, 'pending')
  ON CONFLICT ON CONSTRAINT ledger_anchor_journal_key DO NOTHING;

  RETURN NULL;
END
$enq$;

DROP TRIGGER IF EXISTS ledger_journal_anchor_enqueue ON public.ledger_journal;
CREATE CONSTRAINT TRIGGER ledger_journal_anchor_enqueue
  AFTER INSERT ON public.ledger_journal
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.ledger_anchor_enqueue();

-- Batches posted before this migration existed. Same hash function, same
-- rules; they simply join the back of the queue.
INSERT INTO public.ledger_anchor
  (journal_id, content_hash, chain_id, required_confirmations, status, enqueued_at)
SELECT j.id,
       public.ledger_anchor_content_hash(j.id),
       c.chain_id,
       c.required_confirmations,
       'pending',
       j.posted_at
  FROM public.ledger_journal j
  LEFT JOIN public.ledger_anchor a ON a.journal_id = j.id
  LEFT JOIN LATERAL (SELECT chain_id, required_confirmations
                       FROM public.ledger_anchor_chain WHERE is_default) c ON true
 WHERE a.id IS NULL
ON CONFLICT ON CONSTRAINT ledger_anchor_journal_key DO NOTHING;


-- =====================================================================
-- 5. THE QUEUE AND THE CLAIM
-- =====================================================================

-- What still needs anchoring, oldest first.
--
-- security_invoker so the caller's RLS applies rather than the view owner's:
-- an admin sees the backlog, a member sees nothing.
--
-- A batch is work if it has no receipt. A batch that HAS a receipt is never
-- work again, whatever its status -- including 'failed'. Re-submitting a
-- transaction that may already be in a mempool is exactly the double-submission
-- this design refuses to make automatic; that path is ledger_anchor_reset,
-- which a human calls deliberately.
DROP VIEW IF EXISTS public.ledger_anchor_queue;
CREATE VIEW public.ledger_anchor_queue WITH (security_invoker = true) AS
SELECT j.id                            AS journal_id,
       j.reference,
       j.reason,
       j.posted_at,
       j.entry_count,
       a.id                            AS anchor_id,
       coalesce(a.ledger_label, 'SourceLess HEX') AS ledger_label,
       a.content_hash,
       a.chain_id,
       coalesce(a.status, 'unenqueued') AS status,
       a.attempts,
       a.last_error,
       a.claimed_by,
       a.lease_expires_at,
       (a.id IS NULL)                  AS missing_anchor_row,
       (a.lease_expires_at IS NOT NULL AND a.lease_expires_at > now()) AS leased,
       now() - j.posted_at             AS age
  FROM public.ledger_journal j
  LEFT JOIN public.ledger_anchor a ON a.journal_id = j.id
 WHERE a.id IS NULL
    OR (a.tx_hash IS NULL AND a.status IN ('pending','failed'))
 ORDER BY j.posted_at, j.id;

COMMENT ON VIEW public.ledger_anchor_queue IS
  'SourceLess HEX: batches with no chain receipt yet, oldest first. LEFT JOIN from ledger_journal on purpose -- a batch with no anchor row shows as missing_anchor_row rather than vanishing from the queue.';

-- The service-role gate, shared by every write below.
--
-- Note what cannot be used: current_user is the OWNER inside a SECURITY
-- DEFINER function. What survives is the JWT role PostgREST puts in the GUC
-- and the login role, which is 'authenticator' for any browser session.
CREATE OR REPLACE FUNCTION public.ledger_anchor_assert_service(p_what text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $svc$
DECLARE
  v_jwt_role text;
BEGIN
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  IF v_jwt_role NOT IN ('', 'service_role')
     OR session_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION '% is a service-role operation (caller jwt role %, login role %). The anchoring worker runs server-side; keys never reach the browser.',
      p_what, coalesce(nullif(v_jwt_role, ''), 'none'), session_user
      USING ERRCODE = '42501';
  END IF;
END
$svc$;

-- The read gate for the auditor surface.
--
-- Note the shape: a session is a SERVER session only when the JWT role and the
-- login role BOTH say so. Writing it as `... OR session_user IN
-- ('postgres',...)` would be a hole -- inside psql, and in any pooled
-- connection, session_user is 'postgres' whatever role the request carries, so
-- an OR would wave every browser request straight through. The verification
-- run caught exactly that; this is the corrected form and it matches the guard
-- post_entries uses.
CREATE OR REPLACE FUNCTION public.ledger_anchor_assert_reader(p_what text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $rdr$
DECLARE
  v_jwt_role text;
  v_server   boolean;
BEGIN
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  v_server := v_jwt_role IN ('', 'service_role')
              AND session_user IN ('postgres', 'supabase_admin', 'service_role');

  IF NOT (v_server OR public.is_admin(auth.uid())) THEN
    RAISE EXCEPTION '% is for administrators and auditors (caller jwt role %, login role %)',
      p_what, coalesce(nullif(v_jwt_role, ''), 'none'), session_user
      USING ERRCODE = '42501';
  END IF;
END
$rdr$;

-- Take the next batches to anchor, and lease them.
--
-- FOR UPDATE SKIP LOCKED means two workers running at once take disjoint sets
-- rather than colliding, and a worker that dies leaves a lease that lapses
-- rather than a batch that is stuck. Resumption after an interruption is
-- therefore the ordinary path, not a recovery procedure.
--
-- The refusal at the top is the point of this whole design. With no reachable
-- chain there is nothing honest to return, so it raises and names the reason
-- recorded in the registry. It does NOT return an empty set, because "no work"
-- and "anchoring is broken" are different facts and a worker that cannot tell
-- them apart will log 'nothing to do' forever.
CREATE OR REPLACE FUNCTION public.ledger_anchor_claim(
  p_worker        text,
  p_limit         int DEFAULT 10,
  p_lease_seconds int DEFAULT 300)
RETURNS TABLE (
  journal_id             uuid,
  reference              text,
  content_hash           text,
  hash_algorithm         text,
  chain_id               int,
  rpc_url                text,
  anchor_target          text,
  contract_address       text,
  tx_hash_pattern        text,
  required_confirmations int,
  attempt_no             int,
  lease_expires_at       timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $claim$
-- The RETURNS TABLE columns are deliberately named after the columns they
-- carry (journal_id, chain_id, ...), which makes them plpgsql variables that
-- shadow those very columns inside the body. Nothing here reads an OUT
-- parameter, so the column always wins.
#variable_conflict use_column
DECLARE
  v_chain public.ledger_anchor_chain%ROWTYPE;
  v_lease timestamptz;
  v_open  bigint;
BEGIN
  PERFORM public.ledger_anchor_assert_service('ledger_anchor_claim');

  IF p_worker IS NULL OR btrim(p_worker) = '' THEN
    RAISE EXCEPTION 'p_worker is required: a lease nobody owns cannot be released'
      USING ERRCODE = '22023';
  END IF;
  IF coalesce(p_limit, 0) < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'p_limit must be between 1 and 500' USING ERRCODE = '22023';
  END IF;
  IF coalesce(p_lease_seconds, 0) < 30 OR p_lease_seconds > 3600 THEN
    RAISE EXCEPTION 'p_lease_seconds must be between 30 and 3600' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_chain FROM public.ledger_anchor_chain WHERE is_default;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SourceLess HEX anchoring cannot run: no default chain is registered in ledger_anchor_chain. The ledger keeps posting -- balances do not depend on this -- but nothing is being anchored.'
      USING ERRCODE = '55000';
  END IF;

  IF NOT v_chain.enabled THEN
    SELECT count(*) INTO v_open FROM public.ledger_anchor_queue;
    RAISE EXCEPTION 'SourceLess HEX anchoring is not live: chain % (%) is disabled. % batch(es) are waiting. Reason on record: %',
      v_chain.chain_id, v_chain.name, v_open, v_chain.disabled_reason
      USING ERRCODE = '55000';
  END IF;

  v_lease := now() + make_interval(secs => p_lease_seconds);

  -- Any journal in the queue that has no anchor row gets one now, so the claim
  -- below has something to lease. Hashing here rather than at posting time is
  -- the fallback path; the deferred trigger is what normally stamps the hash
  -- inside the posting transaction.
  INSERT INTO public.ledger_anchor
    (journal_id, content_hash, chain_id, required_confirmations, status, enqueued_at)
  SELECT q.journal_id, public.ledger_anchor_content_hash(q.journal_id),
         v_chain.chain_id, v_chain.required_confirmations, 'pending', q.posted_at
    FROM public.ledger_anchor_queue q
   WHERE q.missing_anchor_row
   ORDER BY q.posted_at, q.journal_id
   LIMIT p_limit
  ON CONFLICT ON CONSTRAINT ledger_anchor_journal_key DO NOTHING;

  RETURN QUERY
  WITH candidate AS (
    SELECT a.id
      FROM public.ledger_anchor a
      JOIN public.ledger_journal j ON j.id = a.journal_id
     WHERE a.tx_hash IS NULL
       AND a.status IN ('pending','failed')
       AND (a.lease_expires_at IS NULL OR a.lease_expires_at <= now())
     ORDER BY j.posted_at, j.id
     LIMIT p_limit
     FOR UPDATE OF a SKIP LOCKED
  ),
  leased AS (
    UPDATE public.ledger_anchor a
       SET claimed_by       = btrim(p_worker),
           claimed_at       = now(),
           lease_expires_at = v_lease,
           attempts         = a.attempts + 1,
           chain_id         = coalesce(a.chain_id, v_chain.chain_id),
           required_confirmations = coalesce(a.required_confirmations,
                                             v_chain.required_confirmations)
      FROM candidate c
     WHERE a.id = c.id
     RETURNING a.id, a.journal_id, a.content_hash, a.hash_algorithm,
               a.chain_id, a.required_confirmations, a.attempts
  ),
  -- A data-modifying CTE runs exactly once and to completion whether or not
  -- the primary query reads it, so every claimed batch is logged even though
  -- nothing selects from here.
  logged AS (
    INSERT INTO public.ledger_anchor_attempt
      (anchor_id, journal_id, attempt_no, outcome, chain_id, worker, detail)
    SELECT l.id, l.journal_id, l.attempts, 'claimed', l.chain_id, btrim(p_worker),
           format('leased until %s', v_lease)
      FROM leased l
    RETURNING 1
  )
  SELECT l.journal_id, j.reference, l.content_hash, l.hash_algorithm,
         l.chain_id, v_chain.rpc_url, v_chain.anchor_target, v_chain.contract_address,
         v_chain.tx_hash_pattern, l.required_confirmations, l.attempts, v_lease
    FROM leased l
    JOIN public.ledger_journal j ON j.id = l.journal_id
   ORDER BY j.posted_at, j.id;
END
$claim$;


-- =====================================================================
-- 6. RECORDING WHAT THE CHAIN SAID
-- =====================================================================

-- A receipt exists. Record it, once.
--
-- Idempotency is the same hash arriving twice: the second call changes nothing
-- and says so. A DIFFERENT hash arriving for a batch that already has one is
-- not idempotent and is not an overwrite either -- it means two transactions
-- were broadcast for one batch. That is recorded as a 'conflict' attempt and
-- refused, because silently keeping either hash would destroy the evidence of
-- the double submission.
CREATE OR REPLACE FUNCTION public.ledger_anchor_record_submission(
  p_journal_id   uuid,
  p_tx_hash      text,
  p_worker       text DEFAULT NULL,
  p_submitted_at timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $sub$
DECLARE
  v_a       public.ledger_anchor%ROWTYPE;
  v_pattern text;
  v_tx      text := lower(btrim(coalesce(p_tx_hash, '')));
BEGIN
  PERFORM public.ledger_anchor_assert_service('ledger_anchor_record_submission');

  IF v_tx = '' THEN
    RAISE EXCEPTION 'p_tx_hash is required. If there is no receipt the batch stays pending -- a placeholder hash is the v2 defect this ledger exists to not repeat.'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_a FROM public.ledger_anchor
   WHERE journal_id = p_journal_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No anchor row for journal % -- claim it before recording a submission for it', p_journal_id
      USING ERRCODE = '22023';
  END IF;

  ------------------------------------------------------------ idempotent
  IF v_a.tx_hash IS NOT NULL AND lower(v_a.tx_hash) = v_tx THEN
    INSERT INTO public.ledger_anchor_attempt
      (anchor_id, journal_id, attempt_no, outcome, tx_hash, chain_id, worker, detail)
    VALUES (v_a.id, v_a.journal_id, v_a.attempts, 'duplicate', v_a.tx_hash,
            v_a.chain_id, p_worker, 'same receipt recorded again; one anchor');
    RETURN jsonb_build_object(
      'recorded', false, 'idempotent', true, 'journal_id', p_journal_id,
      'tx_hash', v_a.tx_hash, 'status', v_a.status,
      'note', 'This transaction hash was already recorded for this batch; nothing changed.');
  END IF;

  -------------------------------------------------------------- conflict
  IF v_a.tx_hash IS NOT NULL THEN
    INSERT INTO public.ledger_anchor_attempt
      (anchor_id, journal_id, attempt_no, outcome, tx_hash, chain_id, worker, detail)
    VALUES (v_a.id, v_a.journal_id, v_a.attempts, 'conflict', v_tx, v_a.chain_id, p_worker,
            format('rejected: batch already anchored by %s', v_a.tx_hash));
    RETURN jsonb_build_object(
      'recorded', false, 'idempotent', false, 'conflict', true,
      'journal_id', p_journal_id,
      'anchored_tx_hash', v_a.tx_hash, 'rejected_tx_hash', v_tx,
      'note', 'Two transactions were broadcast for one batch. The first is kept and the second is logged as a conflict. Reconcile on chain, then use ledger_anchor_reset if the recorded one is dead.');
  END IF;

  --------------------------------------------------------- shape of hash
  SELECT c.tx_hash_pattern INTO v_pattern
    FROM public.ledger_anchor_chain c WHERE c.chain_id = v_a.chain_id;
  IF v_pattern IS NULL THEN
    SELECT tx_hash_pattern INTO v_pattern FROM public.ledger_anchor_chain WHERE is_default;
  END IF;

  IF v_pattern IS NOT NULL AND v_tx !~ v_pattern THEN
    RAISE EXCEPTION 'Refusing tx hash %: it does not match the receipt format % declared for chain %. A value that is not a receipt must not be stored as one.',
      v_tx, v_pattern, coalesce(v_a.chain_id, -1)
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.ledger_anchor
     SET tx_hash          = v_tx,
         status           = 'submitted',
         submitted_at     = coalesce(p_submitted_at, now()),
         confirmations    = 0,
         last_error       = NULL,
         failed_at        = NULL,
         claimed_by       = NULL,
         claimed_at       = NULL,
         lease_expires_at = NULL
   WHERE id = v_a.id;

  INSERT INTO public.ledger_anchor_attempt
    (anchor_id, journal_id, attempt_no, outcome, tx_hash, chain_id, worker, detail)
  VALUES (v_a.id, v_a.journal_id, v_a.attempts, 'submitted', v_tx, v_a.chain_id, p_worker,
          'receipt recorded; awaiting confirmation depth');

  RETURN jsonb_build_object(
    'recorded', true, 'idempotent', false, 'journal_id', p_journal_id,
    'tx_hash', v_tx, 'status', 'submitted',
    'content_hash', v_a.content_hash, 'chain_id', v_a.chain_id);
END
$sub$;


-- Depth, observed. Called on every poll, and allowed to report a SMALLER
-- number than last time -- that is what a reorg looks like from here.
--
-- Crossing the policy depth upward marks the anchor confirmed. Falling back
-- below it un-marks it and increments reorg_count. Nothing in this function
-- treats confirmation as permanent, because on a real chain it is not.
CREATE OR REPLACE FUNCTION public.ledger_anchor_record_confirmation(
  p_journal_id    uuid,
  p_confirmations int,
  p_block_number  bigint DEFAULT NULL,
  p_block_hash    text   DEFAULT NULL,
  p_worker        text   DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $conf$
DECLARE
  v_a        public.ledger_anchor%ROWTYPE;
  v_req      int;
  v_status   text;
  v_reorg    boolean := false;
  v_conf_at  timestamptz;
BEGIN
  PERFORM public.ledger_anchor_assert_service('ledger_anchor_record_confirmation');

  IF p_confirmations IS NULL OR p_confirmations < 0 THEN
    RAISE EXCEPTION 'p_confirmations must be a non-negative observed depth' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_a FROM public.ledger_anchor WHERE journal_id = p_journal_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No anchor row for journal %', p_journal_id USING ERRCODE = '22023';
  END IF;

  IF v_a.tx_hash IS NULL THEN
    RAISE EXCEPTION 'Batch % has no recorded receipt, so it has no depth to confirm. Record the submission first.', p_journal_id
      USING ERRCODE = '22023';
  END IF;

  v_req := coalesce(v_a.required_confirmations,
                    (SELECT required_confirmations FROM public.ledger_anchor_chain
                      WHERE chain_id = v_a.chain_id),
                    (SELECT required_confirmations FROM public.ledger_anchor_chain
                      WHERE is_default));

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'No confirmation policy is on record for chain % -- refusing to decide finality by guesswork',
      coalesce(v_a.chain_id, -1) USING ERRCODE = '55000';
  END IF;

  IF p_confirmations >= v_req THEN
    v_status  := 'confirmed';
    v_conf_at := coalesce(v_a.confirmed_at, now());
  ELSE
    v_status  := 'submitted';
    v_conf_at := NULL;
    v_reorg   := (v_a.status = 'confirmed');
  END IF;

  UPDATE public.ledger_anchor
     SET confirmations          = p_confirmations,
         required_confirmations = v_req,
         block_number           = coalesce(p_block_number, block_number),
         block_hash             = coalesce(nullif(btrim(coalesce(p_block_hash, '')), ''), block_hash),
         status                 = v_status,
         confirmed_at           = v_conf_at,
         failed_at              = NULL,
         last_error             = CASE WHEN v_reorg
                                    THEN format('reorg: depth fell from >=%s to %s', v_req, p_confirmations)
                                    ELSE NULL END,
         reorg_count            = v_a.reorg_count + CASE WHEN v_reorg THEN 1 ELSE 0 END
   WHERE id = v_a.id;

  INSERT INTO public.ledger_anchor_attempt
    (anchor_id, journal_id, attempt_no, outcome, tx_hash, confirmations, chain_id, worker, detail)
  VALUES (v_a.id, v_a.journal_id, v_a.attempts,
          CASE WHEN v_reorg THEN 'reorg'
               WHEN v_status = 'confirmed' THEN 'confirmed'
               ELSE 'submitted' END,
          v_a.tx_hash, p_confirmations, v_a.chain_id, p_worker,
          format('observed depth %s against policy %s', p_confirmations, v_req));

  RETURN jsonb_build_object(
    'journal_id', p_journal_id, 'tx_hash', v_a.tx_hash, 'status', v_status,
    'confirmations', p_confirmations, 'required_confirmations', v_req,
    'reorg_detected', v_reorg,
    'reorg_count', v_a.reorg_count + CASE WHEN v_reorg THEN 1 ELSE 0 END);
END
$conf$;


-- The submission did not produce a receipt, or the chain rejected it.
--
-- A batch with no receipt goes back into the queue immediately: retrying a
-- broadcast that never landed is safe. A batch that already HAS a receipt is
-- marked failed and stays out of the queue, because re-broadcasting over a
-- transaction that may still be in a mempool is the one thing a worker must
-- never do on its own.
CREATE OR REPLACE FUNCTION public.ledger_anchor_record_failure(
  p_journal_id uuid,
  p_error      text,
  p_worker     text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fail$
DECLARE
  v_a public.ledger_anchor%ROWTYPE;
BEGIN
  PERFORM public.ledger_anchor_assert_service('ledger_anchor_record_failure');

  IF p_error IS NULL OR btrim(p_error) = '' THEN
    RAISE EXCEPTION 'p_error is required: a failure that does not say why is indistinguishable from a bug here'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_a FROM public.ledger_anchor WHERE journal_id = p_journal_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No anchor row for journal %', p_journal_id USING ERRCODE = '22023';
  END IF;

  UPDATE public.ledger_anchor
     SET status           = 'failed',
         failed_at        = now(),
         last_error       = btrim(p_error),
         claimed_by       = NULL,
         claimed_at       = NULL,
         lease_expires_at = NULL
   WHERE id = v_a.id;

  INSERT INTO public.ledger_anchor_attempt
    (anchor_id, journal_id, attempt_no, outcome, tx_hash, chain_id, worker, detail)
  VALUES (v_a.id, v_a.journal_id, v_a.attempts, 'failed', v_a.tx_hash, v_a.chain_id,
          p_worker, btrim(p_error));

  RETURN jsonb_build_object(
    'journal_id', p_journal_id, 'status', 'failed',
    'tx_hash', v_a.tx_hash,
    'requeued', (v_a.tx_hash IS NULL),
    'note', CASE WHEN v_a.tx_hash IS NULL
                 THEN 'No receipt was ever recorded, so this batch is back in the queue.'
                 ELSE 'A receipt is on record, so this batch will NOT be resubmitted automatically. Reconcile the transaction on chain and call ledger_anchor_reset if it is dead.' END);
END
$fail$;


-- Supersede a dead transaction. The only way a batch that already has a
-- receipt returns to the queue, and it is deliberate, attributable and
-- non-destructive: the superseded hash is written to the attempt log before it
-- leaves the anchor row.
CREATE OR REPLACE FUNCTION public.ledger_anchor_reset(
  p_journal_id uuid,
  p_reason     text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $reset$
DECLARE
  v_a public.ledger_anchor%ROWTYPE;
BEGIN
  PERFORM public.ledger_anchor_assert_service('ledger_anchor_reset');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'p_reason is required: superseding a recorded receipt must be attributable'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_a FROM public.ledger_anchor WHERE journal_id = p_journal_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No anchor row for journal %', p_journal_id USING ERRCODE = '22023';
  END IF;

  IF v_a.status = 'confirmed' THEN
    RAISE EXCEPTION 'Batch % is confirmed at depth % on %; a confirmed anchor is not reset. If it has been reorged out, record the new depth with ledger_anchor_record_confirmation first.',
      p_journal_id, v_a.confirmations, v_a.tx_hash USING ERRCODE = '22023';
  END IF;

  -- Evidence first, then the amendment.
  INSERT INTO public.ledger_anchor_attempt
    (anchor_id, journal_id, attempt_no, outcome, tx_hash, confirmations, chain_id, worker, detail)
  VALUES (v_a.id, v_a.journal_id, v_a.attempts, 'reset', v_a.tx_hash, v_a.confirmations,
          v_a.chain_id, session_user,
          format('superseded receipt %s: %s', coalesce(v_a.tx_hash, '(none)'), btrim(p_reason)));

  PERFORM set_config('ignitehex.anchor_reset', 'on', true);

  UPDATE public.ledger_anchor
     SET tx_hash          = NULL,
         block_number     = NULL,
         block_hash       = NULL,
         status           = 'pending',
         confirmations    = 0,
         submitted_at     = NULL,
         confirmed_at     = NULL,
         failed_at        = NULL,
         last_error       = format('superseded %s: %s', coalesce(v_a.tx_hash, '(none)'), btrim(p_reason)),
         claimed_by       = NULL,
         claimed_at       = NULL,
         lease_expires_at = NULL
   WHERE id = v_a.id;

  PERFORM set_config('ignitehex.anchor_reset', 'off', true);

  RETURN jsonb_build_object(
    'journal_id', p_journal_id, 'status', 'pending',
    'superseded_tx_hash', v_a.tx_hash,
    'note', 'The superseded receipt is preserved in ledger_anchor_attempt. The batch is back in the queue.');
END
$reset$;


-- =====================================================================
-- 7. VERIFICATION -- THE AUDITOR'S ENTRY POINT
--
-- This is what the whole file is for. Everything above exists so that this
-- can answer one question honestly: do the entries in this database still hash
-- to the value that was published?
--
-- Deliberately read-only. A verifier that can write is a verifier that can be
-- used to launder a discrepancy, so these are STABLE and touch nothing.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ledger_anchor_verify(p_journal_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $ver$
DECLARE
  v_a     public.ledger_anchor%ROWTYPE;
  v_j     public.ledger_journal%ROWTYPE;
  v_now   text;
  v_chain public.ledger_anchor_chain%ROWTYPE;
BEGIN
  PERFORM public.ledger_anchor_assert_reader('ledger_anchor_verify');

  SELECT * INTO v_j FROM public.ledger_journal WHERE id = p_journal_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('journal_id', p_journal_id, 'verdict', 'no_such_batch');
  END IF;

  v_now := public.ledger_anchor_content_hash(p_journal_id);
  SELECT * INTO v_a FROM public.ledger_anchor WHERE journal_id = p_journal_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ledger_label',  'SourceLess HEX',
      'journal_id',    p_journal_id,
      'reference',     v_j.reference,
      'posted_at',     v_j.posted_at,
      'recomputed_hash', v_now,
      'anchored_hash', NULL,
      'verdict',       'not_anchored',
      'explanation',   'This batch has never been enqueued for anchoring. Its entries are still governed by the ledger''s own append-only guarantee, but nothing external attests to them.');
  END IF;

  SELECT * INTO v_chain FROM public.ledger_anchor_chain WHERE chain_id = v_a.chain_id;

  RETURN jsonb_build_object(
    'ledger_label',           v_a.ledger_label,
    'journal_id',             p_journal_id,
    'reference',              v_j.reference,
    'posted_at',              v_j.posted_at,
    'entry_count',            (SELECT count(*) FROM public.ledger_entry e WHERE e.journal_id = p_journal_id),
    'hash_algorithm',         v_a.hash_algorithm,
    'anchored_hash',          v_a.content_hash,
    'recomputed_hash',        v_now,
    'matches',                (v_now = v_a.content_hash),
    'verdict',                CASE
                                WHEN v_now <> v_a.content_hash THEN 'TAMPERED'
                                WHEN v_a.status = 'confirmed'  THEN 'verified_on_chain'
                                WHEN v_a.tx_hash IS NOT NULL   THEN 'verified_locally_awaiting_confirmations'
                                ELSE 'verified_locally_not_yet_anchored'
                              END,
    'chain_id',               v_a.chain_id,
    'chain_name',             v_chain.name,
    'chain_enabled',          coalesce(v_chain.enabled, false),
    'anchor_status',          v_a.status,
    'tx_hash',                v_a.tx_hash,
    'block_number',           v_a.block_number,
    'confirmations',          v_a.confirmations,
    'required_confirmations', v_a.required_confirmations,
    'reorg_count',            v_a.reorg_count,
    'last_error',             v_a.last_error,
    'explorer_url',           CASE WHEN v_a.tx_hash IS NOT NULL AND v_chain.explorer_url IS NOT NULL
                                   THEN rtrim(v_chain.explorer_url, '/') || '/tx/' || v_a.tx_hash END,
    'explanation',            CASE
      WHEN v_now <> v_a.content_hash THEN
        'The entries of this batch no longer hash to the value recorded when it was anchored. Either the entries were altered after the fact or the anchor row was written against different content. Both are incidents.'
      WHEN v_a.status = 'confirmed' THEN
        'The entries hash to the anchored value, and that value is on chain at the recorded depth. Depth is not proof of finality -- re-check it if the chain reorgs.'
      WHEN v_a.tx_hash IS NOT NULL THEN
        'The entries hash to the anchored value and a transaction carrying it has been broadcast, but it has not reached the required depth. Treat it as unanchored until it does.'
      ELSE
        'The entries hash to the value recorded at posting time, but nothing has been published to a chain yet, so there is no external attestation. See ledger_anchor_status().'
    END);
END
$ver$;

-- The sweep. One row per batch in a window, so an auditor can run a single
-- query and read the exceptions off the top.
CREATE OR REPLACE FUNCTION public.ledger_anchor_verify_range(
  p_from timestamptz DEFAULT (now() - interval '30 days'),
  p_to   timestamptz DEFAULT now())
RETURNS TABLE (
  journal_id      uuid,
  reference       text,
  posted_at       timestamptz,
  ledger_label    text,
  anchored_hash   text,
  recomputed_hash text,
  matches         boolean,
  verdict         text,
  anchor_status   text,
  tx_hash         text,
  confirmations   int,
  required_confirmations int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $vrng$
BEGIN
  PERFORM public.ledger_anchor_assert_reader('ledger_anchor_verify_range');

  RETURN QUERY
  SELECT j.id,
         j.reference,
         j.posted_at,
         coalesce(a.ledger_label, 'SourceLess HEX'),
         a.content_hash,
         public.ledger_anchor_content_hash(j.id),
         (a.content_hash IS NOT NULL AND a.content_hash = public.ledger_anchor_content_hash(j.id)),
         CASE
           WHEN a.id IS NULL THEN 'not_anchored'
           WHEN a.content_hash <> public.ledger_anchor_content_hash(j.id) THEN 'TAMPERED'
           WHEN a.status = 'confirmed' THEN 'verified_on_chain'
           WHEN a.tx_hash IS NOT NULL  THEN 'verified_locally_awaiting_confirmations'
           ELSE 'verified_locally_not_yet_anchored'
         END,
         a.status,
         a.tx_hash,
         a.confirmations,
         a.required_confirmations
    FROM public.ledger_journal j
    LEFT JOIN public.ledger_anchor a ON a.journal_id = j.id
   WHERE j.posted_at >= p_from AND j.posted_at <= p_to
   -- exceptions first, then oldest
   ORDER BY (a.id IS NULL
             OR a.content_hash <> public.ledger_anchor_content_hash(j.id)) DESC,
            j.posted_at;
END
$vrng$;

-- The exact bytes the hash is taken over, for an auditor who wants to
-- recompute it outside this database. Admin-gated because a batch payload
-- contains member account identifiers.
CREATE OR REPLACE FUNCTION public.ledger_anchor_export(p_journal_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $exp$
DECLARE
  v_payload text;
BEGIN
  PERFORM public.ledger_anchor_assert_reader('ledger_anchor_export');

  v_payload := public.ledger_anchor_payload(p_journal_id);
  IF v_payload IS NULL THEN
    RETURN jsonb_build_object('journal_id', p_journal_id, 'error', 'no such batch');
  END IF;

  RETURN jsonb_build_object(
    'ledger_label',   'SourceLess HEX',
    'journal_id',     p_journal_id,
    'hash_algorithm', 'sha256/sourceless-hex-anchor-v1',
    'encoding',       'UTF-8, LF line endings, no trailing newline',
    'payload',        v_payload,
    'sha256',         encode(sha256(convert_to(v_payload, 'UTF8')), 'hex'),
    'how_to_check',   'sha256 of the payload bytes, hex, lowercase. Compare against ledger_anchor.content_hash and against the 32 bytes carried by the anchoring transaction.');
END
$exp$;


-- =====================================================================
-- 8. STATUS
--
-- Anchoring that has quietly stopped is worse than anchoring that refuses, so
-- there has to be one call that says which of the two is happening.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ledger_anchor_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $stat$
DECLARE
  v_chain   public.ledger_anchor_chain%ROWTYPE;
  v_open    bigint;
  v_oldest  timestamptz;
  v_healthy boolean;
  v_alert   text;
BEGIN
  PERFORM public.ledger_anchor_assert_reader('ledger_anchor_status');

  SELECT * INTO v_chain FROM public.ledger_anchor_chain WHERE is_default;
  SELECT count(*), min(posted_at) INTO v_open, v_oldest FROM public.ledger_anchor_queue;

  v_healthy := coalesce(v_chain.enabled, false);
  v_alert := CASE
    WHEN v_chain.chain_id IS NULL THEN
      'ANCHORING DOWN: no default chain is registered. Balances are unaffected -- the ledger is authoritative on its own -- but no batch is being published.'
    WHEN NOT v_chain.enabled THEN
      format('ANCHORING DOWN: chain %s (%s) is disabled and %s batch(es) are waiting. %s',
             v_chain.chain_id, v_chain.name, v_open, v_chain.disabled_reason)
    WHEN v_open > 0 AND v_oldest < now() - interval '1 hour' THEN
      format('ANCHORING BEHIND: the oldest unanchored batch is %s old.', now() - v_oldest)
    ELSE NULL
  END;

  RETURN jsonb_build_object(
    'ledger_label', 'SourceLess HEX',
    'healthy',      v_healthy AND v_alert IS NULL,
    'alert',        v_alert,
    'chain', CASE WHEN v_chain.chain_id IS NULL THEN NULL ELSE jsonb_build_object(
      'chain_id',               v_chain.chain_id,
      'name',                   v_chain.name,
      'enabled',                v_chain.enabled,
      'disabled_reason',        v_chain.disabled_reason,
      'rpc_url',                v_chain.rpc_url,
      'explorer_url',           v_chain.explorer_url,
      'anchor_target',          v_chain.anchor_target,
      'contract_address',       v_chain.contract_address,
      'required_confirmations', v_chain.required_confirmations,
      'last_probe_at',          v_chain.last_probe_at,
      'last_probe_ok',          v_chain.last_probe_ok,
      'last_probe_error',       v_chain.last_probe_error) END,
    'journals_total',    (SELECT count(*) FROM public.ledger_journal),
    'queue_depth',       v_open,
    'oldest_unanchored', v_oldest,
    'oldest_unanchored_age', CASE WHEN v_oldest IS NOT NULL THEN (now() - v_oldest)::text END,
    'by_status',         coalesce((SELECT jsonb_object_agg(status, n)
                                     FROM (SELECT status, count(*) AS n
                                             FROM public.ledger_anchor GROUP BY status) s),
                                  '{}'::jsonb),
    'with_receipt',      (SELECT count(*) FROM public.ledger_anchor WHERE tx_hash IS NOT NULL),
    'reorged',           (SELECT count(*) FROM public.ledger_anchor WHERE reorg_count > 0),
    'retried_over_3',    (SELECT count(*) FROM public.ledger_anchor WHERE attempts > 3 AND tx_hash IS NULL),
    'leases_held',       (SELECT count(*) FROM public.ledger_anchor WHERE lease_expires_at > now()));
END
$stat$;


-- =====================================================================
-- 9. PRIVILEGES
--
-- Every function below is REVOKEd from PUBLIC and anon first and granted
-- second. Nothing here widens an existing privilege.
--
-- On tables, RLS is the load-bearing control, not GRANT: rebuild-local.mjs
-- ends with GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated,
-- service_role, which sweeps away any table-level REVOKE a migration performs.
-- The REVOKEs are still stated because they are correct against production.
-- What cannot be swept is the absence of any INSERT/UPDATE/DELETE policy on
-- these tables: a browser role has no write path to them at all.
-- =====================================================================

ALTER TABLE public.ledger_anchor_chain   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_anchor         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_anchor_attempt ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ledger_anchor_chain_admin   ON public.ledger_anchor_chain;
DROP POLICY IF EXISTS ledger_anchor_admin         ON public.ledger_anchor;
DROP POLICY IF EXISTS ledger_anchor_attempt_admin ON public.ledger_anchor_attempt;

CREATE POLICY ledger_anchor_chain_admin   ON public.ledger_anchor_chain
  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY ledger_anchor_admin         ON public.ledger_anchor
  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY ledger_anchor_attempt_admin ON public.ledger_anchor_attempt
  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

REVOKE ALL ON TABLE public.ledger_anchor_chain, public.ledger_anchor,
                    public.ledger_anchor_attempt
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ledger_anchor_chain, public.ledger_anchor,
                      public.ledger_anchor_attempt
  TO authenticated, service_role;

REVOKE ALL    ON TABLE public.ledger_anchor_queue FROM PUBLIC, anon;
GRANT  SELECT ON TABLE public.ledger_anchor_queue TO authenticated, service_role;

-- Internal. Not callable by anyone, including service_role: the write
-- functions reach them because a SECURITY DEFINER function runs as its owner,
-- and the owner owns these too. ledger_anchor_payload in particular reads
-- every member's entries with RLS bypassed -- ledger_anchor_export is the
-- admin-gated way to that data.
REVOKE ALL ON FUNCTION public.ledger_anchor_payload(uuid)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_anchor_content_hash(uuid)     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_anchor_enqueue()              FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_anchor_guard_mutation()       FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_anchor_assert_service(text)   FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_anchor_assert_reader(text)    FROM PUBLIC, anon, authenticated, service_role;

-- Writes: service_role only. The worker runs server-side and the submitting
-- key lives with it; nothing here is reachable from a browser.
REVOKE ALL     ON FUNCTION public.ledger_anchor_claim(text, int, int) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_claim(text, int, int) TO service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_record_submission(uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_record_submission(uuid, text, text, timestamptz) TO service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_record_confirmation(uuid, int, bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_record_confirmation(uuid, int, bigint, text, text) TO service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_record_failure(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_record_failure(uuid, text, text) TO service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_reset(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_reset(uuid, text) TO service_role;

-- Reads: administrators and auditors, plus the service role. Each asserts the
-- caller in its body as well, because the grant has been swept before.
REVOKE ALL     ON FUNCTION public.ledger_anchor_verify(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_verify(uuid) TO authenticated, service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_verify_range(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_verify_range(timestamptz, timestamptz) TO authenticated, service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_export(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_export(uuid) TO authenticated, service_role;

REVOKE ALL     ON FUNCTION public.ledger_anchor_status() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ledger_anchor_status() TO authenticated, service_role;


-- =====================================================================
-- 10. FAIL THE MIGRATION RATHER THAN SHIP A HOLE
-- =====================================================================

DO $verify$
DECLARE
  v_bad     text;
  v_chain   record;
  v_missing bigint;
BEGIN
  -- No browser role may reach a write path or the raw payload.
  SELECT string_agg(format('%s -> %s', p.oid::regprocedure, r.rolname), ', ')
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
   WHERE n.nspname = 'public'
     AND p.proname IN ('ledger_anchor_claim','ledger_anchor_record_submission',
                       'ledger_anchor_record_confirmation','ledger_anchor_record_failure',
                       'ledger_anchor_reset','ledger_anchor_payload',
                       'ledger_anchor_content_hash','ledger_anchor_enqueue',
                       'ledger_anchor_assert_service','ledger_anchor_assert_reader')
     AND has_function_privilege(r.rolname, p.oid, 'EXECUTE');

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'SourceLess HEX anchoring writes are reachable by a browser role: %', v_bad;
  END IF;

  -- anon may not read the anchor tables at all.
  SELECT string_agg(t.relname, ', ') INTO v_bad
    FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace
   WHERE n.nspname = 'public'
     AND t.relname IN ('ledger_anchor','ledger_anchor_chain','ledger_anchor_attempt')
     AND has_table_privilege('anon', t.oid, 'SELECT');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'anon can still read SourceLess HEX anchor tables: %', v_bad;
  END IF;

  -- No write policy may exist on any anchor table.
  SELECT string_agg(format('%s.%s', schemaname, tablename) || ':' || policyname, ', ')
    INTO v_bad
    FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename IN ('ledger_anchor','ledger_anchor_chain','ledger_anchor_attempt')
     AND cmd <> 'SELECT';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'A write policy exists on a SourceLess HEX anchor table: %', v_bad;
  END IF;

  -- The deferred enqueue trigger must be there, or nothing gets hashed at
  -- posting time and the window for undetected alteration opens.
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'ledger_journal_anchor_enqueue'
                    AND tgrelid = 'public.ledger_journal'::regclass
                    AND tgdeferrable) THEN
    RAISE EXCEPTION 'ledger_journal_anchor_enqueue is missing or not deferrable';
  END IF;

  -- Everything already posted must have an anchor row.
  SELECT count(*) INTO v_missing
    FROM public.ledger_journal j
    LEFT JOIN public.ledger_anchor a ON a.journal_id = j.id
   WHERE a.id IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'SourceLess HEX: % existing journal batch(es) were not enqueued', v_missing;
  END IF;

  -- No anchor may claim a receipt it does not have.
  IF EXISTS (SELECT 1 FROM public.ledger_anchor
              WHERE status IN ('submitted','confirmed') AND tx_hash IS NULL) THEN
    RAISE EXCEPTION 'SourceLess HEX: an anchor claims a chain status with no transaction hash';
  END IF;

  SELECT * INTO v_chain FROM public.ledger_anchor_chain WHERE is_default;

  RAISE NOTICE 'SourceLess HEX: anchor layer installed. % batch(es) enqueued.',
    (SELECT count(*) FROM public.ledger_anchor);

  IF v_chain.enabled THEN
    RAISE NOTICE 'SourceLess HEX: anchoring to chain % (%) via %',
      v_chain.chain_id, v_chain.name, v_chain.rpc_url;
  ELSE
    RAISE WARNING 'SourceLess HEX: ANCHORING IS NOT LIVE. Chain % (%) is disabled -- %. Balances are unaffected; ledger_anchor_claim() will refuse rather than pretend.',
      v_chain.chain_id, v_chain.name, v_chain.disabled_reason;
  END IF;
END
$verify$;
