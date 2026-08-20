-- F-005: identity checks written against current_user / session_user are inert
-- inside a SECURITY DEFINER function.
--
-- MEASURED, not assumed. A probe function, SECURITY DEFINER, owner postgres,
-- called four ways against the self-hosted stack:
--
--   caller                     current_user   session_user     role GUC        auth.uid()
--   ------------------------   ------------   --------------   -------------   ----------
--   member (newbie, PostgREST) postgres       authenticator    authenticated   c38c87a9-…
--   anon   (PostgREST)         postgres       authenticator    anon            null
--   service_role (PostgREST)   postgres       authenticator    service_role    null
--   psql -U postgres           postgres       postgres         none            null
--
-- Two conclusions, and they are NOT the same conclusion:
--
--   current_user is 'postgres' for EVERY caller, including anon. It is the
--   function owner. Any test of the form `current_user = 'postgres'` is a
--   constant true and admits everybody.
--
--   session_user is 'authenticator' for every PostgREST caller and 'postgres'
--   only for a direct superuser login. So `session_user = 'postgres'` is NOT
--   a hole - it is a correct, narrow bypass for psql, migrations and pg_cron.
--   (Production agrees: pg_stat_activity there shows 16 PostgREST backends
--   logged in as `authenticator`, none as `postgres`.)
--
-- The project-wide sweep of public functions for the two idioms as bare
-- keywords - matched with word boundaries, so the local variable name
-- `current_user_id` does not count - found seven on this stack:
--
--   _current_is_privileged()                     session_user  BENIGN
--   ledger_anchor_assert_reader(text)            session_user  CORRECT (reference)
--   ledger_anchor_assert_service(text)           session_user  CORRECT (reference)
--   ledger_anchor_reset(uuid,text)               session_user  BENIGN (audit column)
--   ledger_resolve_account(uuid,text,text)       session_user  BENIGN (audit column)
--   post_entries(jsonb,text,text)                both          CORRECT + audit column
--   prevent_user_profile_privilege_escalation()  both          LOAD-BEARING AND INERT
--
-- No RLS policy, column default or check constraint in `public` uses either
-- idiom, locally or in production.
--
-- Exactly one is a live authorisation decision written the inert way, and this
-- migration fixes that one. Production carries the identical function, so this
-- is a defect in the application schema, not in the platform.

BEGIN;

-- ===========================================================================
-- prevent_user_profile_privilege_escalation
-- ===========================================================================
-- The trigger is BEFORE UPDATE on public.user_profiles. Its job is to revert
-- privilege-bearing columns unless the writer is an administrator or a
-- server-side context. Its bypass condition was:
--
--     is_service := (current_setting('request.jwt.claim.role', true) = 'service_role')
--                   OR (session_user = 'postgres')
--                   OR (current_user  = 'postgres');
--
-- The third disjunct is unconditionally true, so `is_service` was always true,
-- so the function returned NEW on its first branch for every caller and never
-- reverted anything. The first disjunct never fired either: PostgREST on this
-- stack populates `request.jwt.claims` (the whole JSON object) and leaves the
-- singular `request.jwt.claim.role` unset - the probe above read it as NULL
-- for all four callers.
--
-- The replacement follows ledger_anchor_assert_reader / assert_caller_owns:
-- read the role out of the JWT, and treat the login role as meaningful ONLY in
-- the case where there is no JWT at all. Neither is trusted alone.
--
--   * A browser request always carries a JWT role of 'authenticated' or
--     'anon', so it can never reach the server branch no matter what the
--     login role is. This is what the old code got wrong.
--   * A service_role request is admitted on its JWT role alone, because that
--     token is signed with the project's JWT secret and never reaches a
--     browser. It does NOT depend on the login role, which is 'authenticator'
--     for a service-key call through PostgREST just as it is for a member.
--   * psql, the migration runner and pg_cron have no JWT, and are admitted on
--     the login role - which for them genuinely is a superuser role.
--
-- Behaviour is otherwise unchanged: a non-admin's writes to the protected
-- columns are silently reverted, not raised on, exactly as before. This is
-- deliberately not widened into a RAISE - several of these columns are
-- already defended by neighbouring triggers that do raise, and turning a
-- silent revert into an error would change what the API returns for writes
-- that today succeed-with-no-effect.

CREATE OR REPLACE FUNCTION public.prevent_user_profile_privilege_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jwt_role text;
  v_server   boolean;
  v_admin    boolean := false;
BEGIN
  -- The caller's role as asserted by the JWT PostgREST verified. This is the
  -- only thing in the session that varies with who is calling.
  v_jwt_role := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    '');

  -- Server-side context. The two arms are disjoint on purpose: a signed
  -- service_role token, or no token at all from a superuser login. A browser
  -- satisfies neither.
  v_server := v_jwt_role = 'service_role'
              OR (v_jwt_role = '' AND session_user IN ('postgres', 'supabase_admin'));

  IF v_server THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_admin := public.has_role(auth.uid(), 'admin'::app_role)
               OR public.has_role(auth.uid(), 'seed_str_admin'::app_role);
  EXCEPTION WHEN OTHERS THEN
    v_admin := false;
  END;

  IF v_admin THEN
    RETURN NEW;
  END IF;

  -- Non-admin, non-server: revert the privilege-bearing columns.
  NEW.status                := OLD.status;
  NEW.user_status           := OLD.user_status;
  NEW.two_factor_enabled    := OLD.two_factor_enabled;
  NEW.two_factor_secret     := OLD.two_factor_secret;
  NEW.wallet_pin_hash       := OLD.wallet_pin_hash;
  NEW.wallet_recovery_words := OLD.wallet_recovery_words;
  NEW.backup_codes          := OLD.backup_codes;

  RETURN NEW;
END;
$$;

-- Trigger functions are resolved at CREATE TRIGGER time, so revoking EXECUTE
-- does not disarm the trigger - it only stops anyone invoking it directly.
-- REVOKE before GRANT, and nothing is granted back: nobody needs to call this.
REVOKE ALL ON FUNCTION public.prevent_user_profile_privilege_escalation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prevent_user_profile_privilege_escalation() FROM anon, authenticated;

COMMENT ON FUNCTION public.prevent_user_profile_privilege_escalation() IS
  'F-005: the previous body bypassed on current_user = ''postgres'', which inside a SECURITY DEFINER function owned by postgres is a constant true, so the guard admitted every caller. Identity now comes from the verified JWT role, with the login role consulted only when there is no JWT.';

COMMIT;

-- ===========================================================================
-- Deliberately NOT changed here, and why
-- ===========================================================================
-- _current_is_privileged() bypasses on
--     current_setting('role', true) = 'service_role' OR session_user = 'postgres'
-- Both arms are sound on the measurements above: the `role` GUC is what
-- PostgREST SET ROLEs to from the verified JWT ('authenticated' for a member,
-- 'anon' for anon), and session_user is 'authenticator' for every PostgREST
-- caller. A member reaches neither arm and falls through to
-- is_admin(auth.uid()). It is consumed by five *_tamper triggers. Benign.
--
-- ledger_anchor_assert_service / assert_reader / post_entries pair the JWT role
-- with session_user using AND, which is the right shape, but they require
-- session_user IN ('postgres','supabase_admin','service_role') - and a genuine
-- service-key call through PostgREST logs in as 'authenticator'. Measured:
--
--   POST /rest/v1/rpc/ledger_anchor_claim with the service_role key
--   -> HTTP 403 "ledger_anchor_claim is a service-role operation
--      (caller jwt role service_role, login role authenticator)"
--
-- That is fail-CLOSED, not fail-open: it refuses the legitimate anchoring
-- worker rather than admitting a member. It is a real defect and it is logged
-- as F-030, but relaxing the login-role set would widen privilege as a side
-- effect of an F-005 fix, so it is left for an explicit decision.
