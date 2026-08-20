-- =====================================================================
-- MEMBER CONNECTION ACTIONS  (closes F-055)
--
-- A member could raise a connection request and then do nothing else with it
-- ever again. The own-update policy on v2_service_connections reads
--
--   USING  (user_id = auth.uid() AND status IN ('not_connected','rejected'))
--   CHECK  (user_id = auth.uid() AND status IN ('not_connected','requested'))
--
-- so a row sitting at `requested` or `connected` matches the USING clause zero
-- times. The update therefore affects no rows — and PostgREST reports that as
-- `200 []` with no error, which the UI had no way to tell apart from success.
-- Two things a member obviously needs were therefore missing:
--
--   * cancel a request they have not been granted yet
--   * disconnect a link they no longer want
--
-- WHY A FUNCTION RATHER THAN A WIDER POLICY: widening the USING clause to admit
-- `connected` would also widen what the CHECK has to defend, and the one
-- guarantee this feature rests on is that a member can never write
-- `connected` themselves. Keeping the policy narrow and putting the member's
-- transitions in one function means that guarantee is stated once, here, and is
-- testable as a unit.
--
-- WHAT THIS DOES NOT CLAIM: nothing here contacts str.domains, strdome.com or
-- ccoin.finance. No API to those properties exists on this deployment. This
-- changes the state of a link record HELD BY IGNITEHEX, which is exactly what
-- the Connected accounts page already tells the member a badge means. The UI
-- must keep saying so — a "disconnect" that silently implied the far side had
-- been told would be a worse lie than the button being absent.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.v2_member_set_connection(
  p_service text,
  p_status  text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $mc$
DECLARE
  v_actor   uuid := auth.uid();
  v_current text;
  v_id      uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Sign in first' USING ERRCODE = '42501';
  END IF;

  -- The states a MEMBER may put their own link into. `connected`,
  -- `pending_review` and `suspended` are decisions made about the member, not
  -- by them, and are deliberately absent. This is the guarantee the identity
  -- domain rests on and it is asserted here rather than left to the caller.
  IF p_status NOT IN ('requested', 'not_connected') THEN
    RAISE EXCEPTION 'A member may only request or clear a connection, not set %', p_status
      USING ERRCODE = '42501';
  END IF;

  SELECT id, status INTO v_id, v_current
    FROM public.v2_service_connections
   WHERE user_id = v_actor AND service = p_service
   FOR UPDATE;

  IF v_id IS NULL THEN
    -- No row yet: only a request makes sense, and the member owns it.
    IF p_status <> 'requested' THEN
      RAISE EXCEPTION 'There is no connection to clear' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.v2_service_connections (user_id, service, status, requested_at)
    VALUES (v_actor, p_service, 'requested', now())
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id, 'from', '(none)', 'to', 'requested');
  END IF;

  -- Transitions a member may make, stated as a table rather than as scattered
  -- conditionals so the whole permitted set is readable at once.
  --
  --   not_connected -> requested       ask for the link
  --   rejected      -> requested       ask again after a refusal
  --   requested     -> not_connected   withdraw a request not yet decided
  --   connected     -> not_connected   end a link the member no longer wants
  --   suspended     -> (nothing)       an administrator suspended it; only they lift it
  IF NOT (
       (v_current IN ('not_connected', 'rejected') AND p_status = 'requested')
    OR (v_current IN ('requested', 'connected')    AND p_status = 'not_connected')
  ) THEN
    RAISE EXCEPTION 'A connection cannot go from % to % from here', v_current, p_status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.v2_service_connections
     SET status       = p_status,
         requested_at = CASE WHEN p_status = 'requested' THEN now() ELSE requested_at END,
         -- Clearing a link clears the date it was granted; leaving a stale
         -- connected_at on a disconnected row makes the history read wrongly.
         connected_at = CASE WHEN p_status = 'not_connected' THEN NULL ELSE connected_at END
   WHERE id = v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'from', v_current, 'to', p_status);
END $mc$;

-- Postgres grants EXECUTE to PUBLIC at creation. This project already carries
-- 269 SECURITY DEFINER functions in production that were never revoked
-- (finding F-001); do not add another.
REVOKE ALL ON FUNCTION public.v2_member_set_connection(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.v2_member_set_connection(text, text) TO authenticated, service_role;
