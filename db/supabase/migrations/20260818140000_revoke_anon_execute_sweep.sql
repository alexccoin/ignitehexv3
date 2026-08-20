-- Remove anon's default EXECUTE on privileged functions.
--
-- Postgres grants EXECUTE to PUBLIC on every function at creation. Across 723
-- migrations that default was revoked for roughly 29 functions across 15
-- migrations; the other 263 SECURITY DEFINER functions in `public` still carry
-- `=X/postgres` in their ACL, so an unauthenticated caller holds EXECUTE on
-- them — including admin_ban_user, admin_confirm_user_email and
-- admin_bulk_create_banking.
--
-- Those functions do check `is_admin(auth.uid())` in their bodies, and that
-- check was verified to hold, so this is not a live breach. It is a missing
-- layer: the moment any function ships without an in-body guard, anon reaches
-- it. Defence in depth means not relying on every future author remembering.
--
-- Scope is deliberately narrow:
--   * anon only. `authenticated` keeps EXECUTE, because the in-body checks
--     (assert_caller_owns, is_admin) are what distinguish a member from an
--     admin, and removing it would break every legitimate member call.
--   * SECURITY DEFINER only. An INVOKER function runs with the caller's own
--     rights, so RLS already contains it.
--   * An allowlist for the few that anon legitimately needs before login.
--
-- Idempotent: REVOKE on an already-revoked function is a no-op.

DO $sweep$
DECLARE
  r record;
  revoked int := 0;
  -- Functions anon must reach before authenticating. Keep this list short and
  -- justify every addition; each entry is a function reachable with no session.
  allowlist text[] := ARRAY[
    'is_domain_available_for_listing',  -- signup flow checks a name before an account exists
    'get_public_token_prices',          -- public marketing figures
    'check_rate_limit',                 -- must work for unauthenticated attempts
    'check_advanced_rate_limit',
    'check_rate_limit_with_progressive_delay',
    'enhanced_rate_limit_check'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prosecdef                              -- SECURITY DEFINER only
       AND NOT (p.proname = ANY (allowlist))
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    -- PUBLIC covers anon, so re-grant the roles that should keep access.
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
    revoked := revoked + 1;
  END LOOP;

  RAISE NOTICE 'revoked anon EXECUTE on % SECURITY DEFINER function(s)', revoked;
END
$sweep$;

-- Stop the default from reappearing on functions created after this point.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
