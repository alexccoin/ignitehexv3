-- =====================================================================
-- F-030 -- the reference identity guards refuse the legitimate service-role
--          caller, so the anchoring worker cannot run over PostgREST.
--
-- WHAT WAS WRONG
--
--   ledger_anchor_assert_service, ledger_anchor_assert_reader and post_entries
--   each decide "is this a server-side caller" with
--
--       jwt_role IN ('', 'service_role') AND session_user IN
--           ('postgres', 'supabase_admin', 'service_role')
--
--   The AND is the defect. PostgREST logs in as `authenticator` and SET ROLEs
--   to the role named in the verified JWT, so a genuine service-key call
--   presents jwt_role = 'service_role' and session_user = 'authenticator' --
--   the same login role a browser presents. The conjunction therefore refuses
--   the anchoring worker, and post_entries names its own contradiction in the
--   error text it raises.
--
--   Measured on this stack before the change, over real HTTP:
--
--       POST /rest/v1/rpc/ledger_anchor_claim   service key
--         -> 403 42501 "ledger_anchor_claim is a service-role operation
--            (caller jwt role service_role, login role authenticator)"
--       POST /rest/v1/rpc/ledger_anchor_status  service key
--         -> 403 42501 "... is for administrators and auditors
--            (caller jwt role service_role, login role authenticator)"
--       same claim from psql (no JWT, session_user postgres)
--         -> passes the guard, reaches the business rule (chain disabled)
--
--   Fail-CLOSED, so nothing was ever exposed by it. Anchoring simply could
--   only be driven from psql.
--
-- WHAT REPLACES IT
--
--   The shape F-005's fix settled on. Identity comes from the verified JWT
--   role. The login role is consulted only when there is no JWT at all, which
--   is the psql / pg_cron / migration case:
--
--       server := jwt_role = 'service_role'
--                 OR (jwt_role = '' AND login role IN (postgres, supabase_admin))
--
--   A browser always carries a JWT role of `authenticated` or `anon`, so it
--   fails the first arm and is disqualified from the second by carrying a JWT
--   at all. That is the property the old code was reaching for and inverted.
--
-- WHY THIS DOES NOT WIDEN PRIVILEGE
--
--   1. The JWT role is not caller-asserted. PostgREST verifies the signature
--      against JWT_SECRET before it SET ROLEs, so `role: service_role` in the
--      claims means the caller holds the service key -- which is already a
--      full-privilege credential. Admitting it here grants nothing it could
--      not otherwise reach.
--   2. The EXECUTE grant is the primary control and is unchanged.
--      ledger_anchor_claim is granted to service_role only; anon and
--      authenticated are refused by the grant before the body runs. Measured
--      on this stack: member and admin both get
--      "permission denied for function ledger_anchor_claim".
--   3. `service_role` is dropped from the login-role list. It was dead text:
--      the role is NOLOGIN on this stack and in production, so session_user
--      can never equal it. Removing it narrows nothing and stops the list
--      reading as though a JWT-less service_role session were a real context.
--   4. The reader guard keeps its is_admin(auth.uid()) arm untouched, so an
--      administrator's access to the anchor status and verification functions
--      is exactly what it was.
--
-- NOT APPLIED TO PRODUCTION.
-- =====================================================================


-- ---------------------------------------------------------------------
-- ledger_anchor_assert_service(text)
--
-- Used by ledger_anchor_claim, ledger_anchor_record_submission,
-- ledger_anchor_record_confirmation, ledger_anchor_record_failure and
-- ledger_anchor_reset. These are the worker's write path and are for a
-- server-side caller only, never an administrator in a browser.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ledger_anchor_assert_service(p_what text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $svc$
DECLARE
  v_jwt_role text;
  v_login    text;
  v_server   boolean;
BEGIN
  -- The verified JWT role. PostgREST populates request.jwt.claims; the
  -- singular request.jwt.claim.role is read only as a fallback for older
  -- callers, and is NULL under this PostgREST (see F-005).
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  -- The login role. Deliberately read into a variable rather than named at the
  -- start of a line: scripts/repair-migrations.mjs rewrites a bare
  -- `session_user` that begins a line into `v_session_user` (F-029 territory).
  v_login := session_user;

  v_server := v_jwt_role = 'service_role'
              OR (v_jwt_role = '' AND v_login IN ('postgres', 'supabase_admin'));

  IF NOT v_server THEN
    RAISE EXCEPTION '% is a service-role operation (caller jwt role %, login role %). The anchoring worker runs server-side; keys never reach the browser.',
      p_what, coalesce(nullif(v_jwt_role, ''), 'none'), v_login
      USING ERRCODE = '42501';
  END IF;
END
$svc$;


-- ---------------------------------------------------------------------
-- ledger_anchor_assert_reader(text)
--
-- Used by ledger_anchor_status, ledger_anchor_verify,
-- ledger_anchor_verify_range and ledger_anchor_export. Administrators and
-- auditors read these from the browser; the worker reads them too.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ledger_anchor_assert_reader(p_what text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $rdr$
DECLARE
  v_jwt_role text;
  v_login    text;
  v_server   boolean;
BEGIN
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  v_login := session_user;

  v_server := v_jwt_role = 'service_role'
              OR (v_jwt_role = '' AND v_login IN ('postgres', 'supabase_admin'));

  -- Identity for the human arm is re-derived from the token, never from a
  -- parameter: is_admin reads auth.uid().
  IF NOT (v_server OR public.is_admin(auth.uid())) THEN
    RAISE EXCEPTION '% is for administrators and auditors (caller jwt role %, login role %)',
      p_what, coalesce(nullif(v_jwt_role, ''), 'none'), v_login
      USING ERRCODE = '42501';
  END IF;
END
$rdr$;


-- ---------------------------------------------------------------------
-- post_entries(jsonb, text, text)
--
-- The ledger primitive. Same correction to its section (1) guard and nothing
-- else: the body below is the shipped 20260818160000 text with only the
-- identity test replaced. The delegation marker, the idempotency key, the
-- zero-sum rule, the ordering of the account locks and the projection are all
-- unchanged.
--
-- The comment the old code carried -- "the login role, which is
-- 'authenticator' for every browser session and 'postgres' or 'service_role'
-- for a server one" -- was the false premise. It is corrected in place.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.post_entries(p_entries jsonb, p_reference text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $pe$
DECLARE
  v_ref       text := btrim(coalesce(p_reference, ''));
  v_journal   uuid;
  v_existing  uuid;
  v_legs      public.ledger_leg[];
  v_ids       uuid[] := '{}';
  v_leg       public.ledger_leg;
  v_bad       text;
  v_before    bigint;
  v_after     bigint;
  v_neg       boolean;
  v_out       jsonb := '[]'::jsonb;
  i           int;
  v_jwt_role  text;
  v_login     text;
  v_server    boolean;
  v_delegated boolean;
BEGIN
  -- (1) Not member-callable.
  --
  -- The EXECUTE grant in 20260818160000 section 6 is the primary control and
  -- it is sufficient: anon and authenticated hold nothing on this function.
  -- This is the second lock, because rebuild-local.mjs has swept revoked
  -- functions back open before now and a re-granted post_entries would be the
  -- worst possible thing to hand a browser.
  --
  -- Note what CANNOT be used here. `current_user` is the OWNER inside a
  -- SECURITY DEFINER function, so it reads 'postgres' no matter who called and
  -- is useless as a caller test. The login role is `authenticator` for EVERY
  -- PostgREST caller -- browser and service key alike -- so it cannot separate
  -- them either. Only the verified JWT role can, and it is what decides here.
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  v_login := session_user;

  v_server := v_jwt_role = 'service_role'
              OR (v_jwt_role = '' AND v_login IN ('postgres', 'supabase_admin'));

  -- A wrapper marks its own delegation, transaction-locally and single-use.
  v_delegated := coalesce(current_setting('ignitehex.ledger_delegated', true), 'off') = 'on';
  PERFORM set_config('ignitehex.ledger_delegated', 'off', true);

  IF NOT v_delegated AND NOT v_server THEN
    RAISE EXCEPTION 'post_entries is a service-role primitive (caller jwt role %, login role %). Member operations must go through a wrapper that asserts identity.',
      coalesce(nullif(v_jwt_role, ''), 'none'), v_login
      USING ERRCODE = '42501';
  END IF;

  IF v_ref = '' THEN
    RAISE EXCEPTION 'p_reference is required: it is the idempotency key' USING ERRCODE = '22023';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'p_reason is required: every balance change must be attributable' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) < 2 THEN
    RAISE EXCEPTION 'p_entries must be an array of at least two legs' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) e
     WHERE e->>'user_id' IS NULL OR e->>'asset' IS NULL
        OR e->>'bucket'  IS NULL OR e->>'amount' IS NULL
  ) THEN
    RAISE EXCEPTION 'Every entry needs user_id, asset, bucket and amount' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entries) e
     WHERE (e->>'amount')::numeric <> trunc((e->>'amount')::numeric)
  ) THEN
    RAISE EXCEPTION 'Amounts are integers in the asset''s minor units; a fractional amount would have to be rounded, and a rounded credit is a mint'
      USING ERRCODE = '22003';
  END IF;

  -- (2) Idempotency. ON CONFLICT DO NOTHING also serialises two concurrent
  -- posts of the same reference: the loser blocks, then sees zero rows.
  INSERT INTO public.ledger_journal (reference, reason, posted_by, posted_role, entry_count)
  VALUES (v_ref, btrim(p_reason), auth.uid(), v_login, jsonb_array_length(p_entries))
  ON CONFLICT ON CONSTRAINT ledger_journal_reference_key DO NOTHING
  RETURNING id INTO v_journal;

  IF v_journal IS NULL THEN
    SELECT id INTO v_existing FROM public.ledger_journal WHERE reference = v_ref;
    RETURN jsonb_build_object(
      'applied',   false,
      'idempotent', true,
      'reference', v_ref,
      'journal_id', v_existing,
      'note', 'This reference has already been posted; nothing was changed.');
  END IF;

  -- (3) Zero-sum per asset.
  SELECT string_agg(format('%s=%s', asset, net), ', ' ORDER BY asset) INTO v_bad
    FROM (
      SELECT upper(btrim(e->>'asset')) AS asset, sum((e->>'amount')::bigint) AS net
        FROM jsonb_array_elements(p_entries) e
       GROUP BY 1
      HAVING sum((e->>'amount')::bigint) <> 0
    ) x;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Unbalanced batch rejected: signed amounts must sum to zero per asset, but the net residual is [%]. Every credit needs a named account the value came out of.', v_bad
      USING ERRCODE = '23514';
  END IF;

  -- Net the legs per account so each account is locked and written once.
  SELECT array_agg(ROW(user_id, asset, bucket, amount)::public.ledger_leg
                   ORDER BY user_id, asset, bucket)
    INTO v_legs
    FROM (
      SELECT (e->>'user_id')::uuid       AS user_id,
             upper(btrim(e->>'asset'))   AS asset,
             lower(btrim(e->>'bucket'))  AS bucket,
             sum((e->>'amount')::bigint) AS amount
        FROM jsonb_array_elements(p_entries) e
       GROUP BY 1, 2, 3
      HAVING sum((e->>'amount')::bigint) <> 0
    ) s;

  IF v_legs IS NULL OR array_length(v_legs, 1) IS NULL THEN
    RAISE EXCEPTION 'Batch has no net effect: every leg cancels against another on the same account'
      USING ERRCODE = '22023';
  END IF;

  -- Resolve accounts in the same deterministic order the legs are sorted in.
  FOREACH v_leg IN ARRAY v_legs LOOP
    v_ids := v_ids || public.ledger_resolve_account(v_leg.user_id, v_leg.asset, v_leg.bucket);
  END LOOP;

  -- (4) Lock every touched account, ascending id. Two batches over the same
  -- accounts therefore always take them in the same order.
  PERFORM 1 FROM public.ledger_account
   WHERE id = ANY (v_ids) ORDER BY id FOR UPDATE;

  -- (5)+(6) Guard the sign under the lock, apply, project, record.
  FOR i IN 1 .. array_length(v_legs, 1) LOOP
    v_leg := v_legs[i];

    SELECT balance, allow_negative INTO v_before, v_neg
      FROM public.ledger_account WHERE id = v_ids[i];

    IF v_before + v_leg.amount < 0 AND NOT v_neg THEN
      RAISE EXCEPTION 'Insufficient balance: %/%/% holds % minor units and the batch would take it to %',
        v_leg.user_id, v_leg.asset, v_leg.bucket, v_before, v_before + v_leg.amount
        USING ERRCODE = '23514';
    END IF;

    UPDATE public.ledger_account
       SET balance = balance + v_leg.amount, updated_at = now()
     WHERE id = v_ids[i]
    RETURNING balance INTO v_after;

    PERFORM public.ledger_apply_projection(v_leg.user_id, v_leg.asset, v_leg.bucket, v_leg.amount);

    INSERT INTO public.ledger_entry (journal_id, account_id, asset, amount, balance_after)
    VALUES (v_journal, v_ids[i], v_leg.asset, v_leg.amount, v_after);

    v_out := v_out || jsonb_build_object(
      'user_id', v_leg.user_id, 'asset', v_leg.asset, 'bucket', v_leg.bucket,
      'amount', v_leg.amount, 'balance_after', v_after,
      'balance_after_major', public.ledger_major(v_leg.asset, v_after));
  END LOOP;

  RETURN jsonb_build_object(
    'applied',   true,
    'idempotent', false,
    'reference', v_ref,
    'journal_id', v_journal,
    'entries',   v_out);
END
$pe$;


-- ---------------------------------------------------------------------
-- Privileges. REVOKE before GRANT, and the posture is exactly what
-- 20260818160000 section 6 set -- restated because CREATE OR REPLACE on a
-- function does not reset its ACL, but a replayed history that recreated one
-- of these from an earlier file would.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.ledger_anchor_assert_service(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ledger_anchor_assert_reader(text)  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL     ON FUNCTION public.post_entries(jsonb, text, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.post_entries(jsonb, text, text) TO service_role;

COMMENT ON FUNCTION public.ledger_anchor_assert_service(text) IS
  'F-030: admits a caller whose VERIFIED JWT role is service_role, or a JWT-less session logged in as postgres/supabase_admin. The login role is authenticator for every PostgREST caller including the service key, so it cannot be required as well.';

COMMENT ON FUNCTION public.ledger_anchor_assert_reader(text) IS
  'F-030: same server test as ledger_anchor_assert_service, plus is_admin(auth.uid()) for administrators and auditors reading from the browser.';
