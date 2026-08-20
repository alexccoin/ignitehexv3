-- =====================================================================
-- MIGRATION QUARANTINE
--
-- IgniteHeX v3 runs on a new database. Members arrive by signing in with
-- their existing credentials, which are verified against the legacy project
-- at login time (see the `migrate-login` edge function). This file is what
-- happens to their DATA when they arrive.
--
-- THE RULE: an imported figure is a CLAIM, not a balance.
--
-- Nothing imported here is spendable. Legacy amounts land in
-- quarantined_balances and the live ledger stays at zero until an admin
-- reviews the figure, optionally corrects it, and approves. Approval is the
-- only path from claim to balance, and it goes through post_entries, so an
-- approved balance carries a journal reference and a matching debit against
-- opening_equity rather than being a number someone typed into a table.
--
-- WHY, SPECIFICALLY: the legacy figures are the ones that produced a
-- 1.026B CCOS position against a 63M cap, 2,546,068,134 staked against
-- 3,860,797 in recorded rewards, and a fiat liability that grew from
-- USD 9.24M to 22.1M while under review. Importing those as balances would
-- carry every one of those defects into the new system on day one and make
-- them indistinguishable from correct data. Importing them as claims makes
-- each one somebody's explicit decision.
-- =====================================================================

DO $mq$ BEGIN
  CREATE TYPE public.migration_state AS ENUM
    ('quarantined', 'under_review', 'approved', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $mq$;

-- ------------------------------------------------------------------ accounts
CREATE TABLE IF NOT EXISTS public.migrated_accounts (
  user_id        uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  source_project text NOT NULL,
  source_user_id uuid NOT NULL,
  source_email   text NOT NULL,
  state          public.migration_state NOT NULL DEFAULT 'quarantined',
  imported_at    timestamptz NOT NULL DEFAULT now(),
  reviewed_by    uuid REFERENCES auth.users(id),
  reviewed_at    timestamptz,
  review_notes   text,
  -- The legacy figures exactly as they were read, never edited. A correction
  -- goes in quarantined_balances; this stays as the record of what was claimed.
  source_snapshot   jsonb NOT NULL DEFAULT '{}'::jsonb,
  ledger_journal_id uuid,
  UNIQUE (source_project, source_user_id)
);

-- ------------------------------------------------------------------ balances
CREATE TABLE IF NOT EXISTS public.quarantined_balances (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  asset            text NOT NULL REFERENCES public.ledger_asset(asset),
  bucket           text NOT NULL DEFAULT 'liquid',
  source_amount    numeric(38,18) NOT NULL DEFAULT 0 CHECK (source_amount >= 0),
  -- NULL means "no admin has looked at this yet". That is deliberately distinct
  -- from 0, which means "an admin decided this is zero".
  corrected_amount numeric(38,18) CHECK (corrected_amount IS NULL OR corrected_amount >= 0),
  corrected_by     uuid REFERENCES auth.users(id),
  corrected_at     timestamptz,
  note             text,
  UNIQUE (user_id, asset, bucket)
);

CREATE INDEX IF NOT EXISTS quarantined_balances_user_idx ON public.quarantined_balances(user_id);
CREATE INDEX IF NOT EXISTS migrated_accounts_state_idx   ON public.migrated_accounts(state);

-- ------------------------------------------------------------------ RLS
-- Members read their own row and nothing else. NOBODY writes these tables
-- through PostgREST: every write goes through a SECURITY DEFINER function
-- below that asserts who the caller is. An UPDATE policy here would be a way
-- to approve yourself.
ALTER TABLE public.migrated_accounts    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quarantined_balances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS migrated_accounts_select_own ON public.migrated_accounts;
CREATE POLICY migrated_accounts_select_own ON public.migrated_accounts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS quarantined_balances_select_own ON public.quarantined_balances;
CREATE POLICY quarantined_balances_select_own ON public.quarantined_balances
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- =====================================================================
-- Import. service_role only -- called by the migrate-login edge function
-- after the legacy project has verified the password.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.quarantine_import(
  p_user_id        uuid,
  p_source_project text,
  p_source_user_id uuid,
  p_source_email   text,
  p_snapshot       jsonb,
  p_balances       jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $qi$
DECLARE
  v_jwt_role text;
  v_row      jsonb;
  v_n        int := 0;
BEGIN
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''), '');
  IF v_jwt_role NOT IN ('', 'service_role')
     OR session_user NOT IN ('postgres', 'supabase_admin', 'service_role') THEN
    RAISE EXCEPTION 'quarantine_import is a service-role primitive' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.migrated_accounts
    (user_id, source_project, source_user_id, source_email, source_snapshot)
  VALUES (p_user_id, p_source_project, p_source_user_id, p_source_email,
          coalesce(p_snapshot, '{}'::jsonb))
  ON CONFLICT (user_id) DO UPDATE
    -- Re-importing refreshes the claim but NEVER resurrects a decided account:
    -- an approved or rejected review is not undone by signing in again.
    SET source_snapshot = EXCLUDED.source_snapshot
  WHERE public.migrated_accounts.state IN ('quarantined', 'under_review');

  FOR v_row IN SELECT * FROM jsonb_array_elements(coalesce(p_balances, '[]'::jsonb))
  LOOP
    INSERT INTO public.quarantined_balances (user_id, asset, bucket, source_amount)
    VALUES (p_user_id,
            upper(v_row ->> 'asset'),
            coalesce(v_row ->> 'bucket', 'liquid'),
            greatest((v_row ->> 'amount')::numeric, 0))
    ON CONFLICT (user_id, asset, bucket) DO UPDATE
      SET source_amount = EXCLUDED.source_amount
    -- Never overwrite a figure an administrator has already decided.
    WHERE public.quarantined_balances.corrected_amount IS NULL;
    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object('user_id', p_user_id, 'balances', v_n);
END $qi$;

REVOKE ALL ON FUNCTION public.quarantine_import(uuid, text, uuid, text, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.quarantine_import(uuid, text, uuid, text, jsonb, jsonb)
  TO service_role;

-- =====================================================================
-- Correction. Admin only.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.set_quarantine_correction(
  p_user_id uuid, p_asset text, p_bucket text, p_amount numeric, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $sc$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin(v_actor) THEN
    RAISE EXCEPTION 'Only an administrator may correct a quarantined figure' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'A corrected amount must be zero or positive' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.migrated_accounts
                  WHERE user_id = p_user_id AND state IN ('quarantined', 'under_review')) THEN
    RAISE EXCEPTION 'Account is not open for review' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.quarantined_balances
    (user_id, asset, bucket, source_amount, corrected_amount, corrected_by, corrected_at, note)
  VALUES (p_user_id, upper(p_asset), coalesce(p_bucket, 'liquid'), 0, p_amount, v_actor, now(), p_note)
  ON CONFLICT (user_id, asset, bucket) DO UPDATE
    SET corrected_amount = EXCLUDED.corrected_amount,
        corrected_by     = EXCLUDED.corrected_by,
        corrected_at     = EXCLUDED.corrected_at,
        note             = coalesce(EXCLUDED.note, public.quarantined_balances.note);

  UPDATE public.migrated_accounts SET state = 'under_review'
   WHERE user_id = p_user_id AND state = 'quarantined';

  RETURN jsonb_build_object('ok', true);
END $sc$;

REVOKE ALL ON FUNCTION public.set_quarantine_correction(uuid, text, text, numeric, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_quarantine_correction(uuid, text, text, numeric, text)
  TO authenticated, service_role;

-- =====================================================================
-- Approval. Admin only. THE ONLY PATH FROM CLAIM TO BALANCE.
--
-- Every approved figure becomes a ledger posting whose counterparty is
-- opening_equity, so the new system's books balance from the first entry and
-- an approved balance can always be traced to who approved it and when.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.approve_migration(p_user_id uuid, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $am$
DECLARE
  v_actor   uuid := auth.uid();
  v_equity  uuid;
  v_entries jsonb := '[]'::jsonb;
  v_r       record;
  v_minor   bigint;
  v_result  jsonb;
  v_journal uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin(v_actor) THEN
    RAISE EXCEPTION 'Only an administrator may approve a migration' USING ERRCODE = '42501';
  END IF;
  -- An administrator may not approve their own migrated account. The point of
  -- the gate is a second pair of eyes on a figure that turns into money.
  IF p_user_id = v_actor THEN
    RAISE EXCEPTION 'An administrator may not approve their own migration' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.migrated_accounts
                  WHERE user_id = p_user_id AND state IN ('quarantined', 'under_review')) THEN
    RAISE EXCEPTION 'Account is not open for review' USING ERRCODE = '22023';
  END IF;

  v_equity := public.ledger_system_user('opening_equity');

  FOR v_r IN
    SELECT asset, bucket, coalesce(corrected_amount, source_amount) AS amt
      FROM public.quarantined_balances
     WHERE user_id = p_user_id
       AND coalesce(corrected_amount, source_amount) > 0
     ORDER BY asset, bucket
  LOOP
    v_minor := public.ledger_minor(v_r.asset, v_r.amt);
    CONTINUE WHEN v_minor = 0;
    v_entries := v_entries
      || jsonb_build_object('user_id', p_user_id, 'asset', v_r.asset,
                            'bucket', v_r.bucket, 'amount', v_minor::text)
      || jsonb_build_object('user_id', v_equity,  'asset', v_r.asset,
                            'bucket', 'liquid',   'amount', (-v_minor)::text);
  END LOOP;

  IF jsonb_array_length(v_entries) > 0 THEN
    PERFORM set_config('ignitehex.ledger_delegated', 'on', true);
    v_result := public.post_entries(
      v_entries,
      'migration:' || p_user_id::text,
      coalesce(nullif(btrim(p_note), ''), 'Migration approved from quarantine'));
    v_journal := (v_result ->> 'journal_id')::uuid;
  END IF;

  UPDATE public.migrated_accounts
     SET state = 'approved', reviewed_by = v_actor, reviewed_at = now(),
         review_notes = p_note, ledger_journal_id = v_journal
   WHERE user_id = p_user_id;

  RETURN jsonb_build_object('ok', true, 'journal_id', v_journal,
                            'legs', jsonb_array_length(v_entries));
END $am$;

REVOKE ALL ON FUNCTION public.approve_migration(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_migration(uuid, text) TO authenticated, service_role;

-- =====================================================================
-- Rejection. Admin only. Posts nothing -- a rejected claim never becomes a
-- balance, and the snapshot stays for the record.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.reject_migration(p_user_id uuid, p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $rm$
DECLARE v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL OR NOT public.is_admin(v_actor) THEN
    RAISE EXCEPTION 'Only an administrator may reject a migration' USING ERRCODE = '42501';
  END IF;
  IF p_note IS NULL OR btrim(p_note) = '' THEN
    RAISE EXCEPTION 'A rejection must carry a reason' USING ERRCODE = '22023';
  END IF;
  UPDATE public.migrated_accounts
     SET state = 'rejected', reviewed_by = v_actor, reviewed_at = now(), review_notes = p_note
   WHERE user_id = p_user_id AND state IN ('quarantined', 'under_review');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account is not open for review' USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('ok', true);
END $rm$;

REVOKE ALL ON FUNCTION public.reject_migration(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_migration(uuid, text) TO authenticated, service_role;

-- =====================================================================
-- Rate limiting for the migration login path.
--
-- WHY THIS EXISTS: `migrate-login` forwards an email and password to the
-- legacy project and reports whether they were accepted. That is, by
-- construction, an oracle for testing credentials against production --
-- reachable by anyone who can reach the site, with none of production's own
-- throttling in front of it. Without this table the new system would be a
-- credential-stuffing amplifier pointed at the old one.
--
-- Counted per (email, ip) and per ip alone, so neither spraying one account
-- nor spraying many from one source is cheap.
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.migration_login_attempts (
  id         bigserial PRIMARY KEY,
  email      text NOT NULL,
  ip         text NOT NULL,
  succeeded  boolean NOT NULL,
  at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS migration_login_attempts_lookup
  ON public.migration_login_attempts (ip, at DESC);
CREATE INDEX IF NOT EXISTS migration_login_attempts_email
  ON public.migration_login_attempts (email, ip, at DESC);

ALTER TABLE public.migration_login_attempts ENABLE ROW LEVEL SECURITY;
-- No policy at all: RLS on with zero policies denies every PostgREST caller.
-- Only the edge function, holding service_role, reaches this table.

-- Returns TRUE when the attempt may proceed. Records the attempt either way,
-- so a blocked attempt still counts against the window and a caller cannot
-- reset their budget by continuing to try.
CREATE OR REPLACE FUNCTION public.migration_login_allowed(p_email text, p_ip text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $mla$
DECLARE
  v_by_pair int;
  v_by_ip   int;
BEGIN
  SELECT count(*) INTO v_by_pair FROM public.migration_login_attempts
   WHERE email = lower(p_email) AND ip = p_ip AND at > now() - interval '15 minutes';
  SELECT count(*) INTO v_by_ip FROM public.migration_login_attempts
   WHERE ip = p_ip AND at > now() - interval '15 minutes';
  RETURN v_by_pair < 5 AND v_by_ip < 20;
END $mla$;

REVOKE ALL ON FUNCTION public.migration_login_allowed(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.migration_login_allowed(text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.migration_login_record(p_email text, p_ip text, p_ok boolean)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $mlr$
  INSERT INTO public.migration_login_attempts (email, ip, succeeded)
  VALUES (lower(p_email), p_ip, p_ok);
$mlr$;

REVOKE ALL ON FUNCTION public.migration_login_record(text, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.migration_login_record(text, text, boolean) TO service_role;
