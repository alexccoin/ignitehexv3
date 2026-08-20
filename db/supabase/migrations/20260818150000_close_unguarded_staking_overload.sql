-- Close the unguarded process_staking_request overload.
--
-- Two overloads exist:
--
--   process_staking_request(request_id uuid, approve boolean, admin_notes_param text)
--     SECURITY DEFINER, checks the caller is an admin in its body. Correct.
--
--   process_staking_request(p_request_id uuid, p_action text, p_admin_notes text)
--     SECURITY DEFINER, NO authorization check of any kind, EXECUTE to
--     authenticated. It opens a staking position and sets its own APY.
--
-- Any signed-in member could call the second one over PostgREST and approve
-- their own staking request, choosing the rate. A frontend role guard does not
-- help: the RPC is reachable directly.
--
-- The unguarded overload is left in place rather than dropped, because a
-- migration later in the history edits it and DROP would break replay. Removing
-- EXECUTE achieves the same containment: the function becomes unreachable from
-- any browser session, and PostgREST stops resolving it at all.

REVOKE EXECUTE ON FUNCTION public.process_staking_request(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.process_staking_request(uuid, text, text) TO service_role;

-- The guarded overload is the one clients use, and keeps its grant.
GRANT  EXECUTE ON FUNCTION public.process_staking_request(uuid, boolean, text) TO authenticated, service_role;

DO $check$
DECLARE
  unguarded_reachable boolean;
BEGIN
  SELECT has_function_privilege('authenticated', p.oid, 'EXECUTE')
    INTO unguarded_reachable
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'process_staking_request'
     AND pg_get_function_identity_arguments(p.oid) = 'p_request_id uuid, p_action text, p_admin_notes text';

  IF unguarded_reachable THEN
    RAISE EXCEPTION 'unguarded process_staking_request overload is still reachable by authenticated';
  END IF;
END
$check$;
