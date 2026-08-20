-- Bulk status updates + archived deletion for profile/queue requests

CREATE OR REPLACE FUNCTION public.v2_admin_bulk_update_requests(
  p_source text,
  p_ids uuid[],
  p_status text,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_id uuid;
  v_ok int := 0;
  v_fail int := 0;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'No requests selected';
  END IF;
  IF array_length(p_ids, 1) > 500 THEN
    RAISE EXCEPTION 'Too many requests in one batch (max 500)';
  END IF;

  FOREACH v_id IN ARRAY p_ids LOOP
    BEGIN
      PERFORM public.v2_admin_update_request(p_source, v_id, p_status, p_notes);
      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      v_fail := v_fail + 1;
      v_errors := v_errors || jsonb_build_object('id', v_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('updated', v_ok, 'failed', v_fail, 'errors', v_errors);
END;
$$;

REVOKE ALL ON FUNCTION public.v2_admin_bulk_update_requests(text, uuid[], text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v2_admin_bulk_update_requests(text, uuid[], text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_admin_bulk_update_requests(text, uuid[], text, text) TO service_role;

-- Delete a request while permanently archiving its full payload in the V2 history
CREATE OR REPLACE FUNCTION public.v2_admin_delete_request(
  p_source text,
  p_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_table text;
  v_user_col text := 'user_id';
  v_status_col text := 'status';
  v_before jsonb;
  v_user uuid;
  v_account uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  CASE p_source
    WHEN 'pending_profile_changes' THEN v_table := 'pending_profile_changes';
    WHEN 'user_profiles_updated' THEN v_table := 'user_profiles_updated'; v_status_col := 'submission_status';
    WHEN 'missing_asset_reports' THEN v_table := 'missing_asset_reports';
    WHEN 'str_dome_requests' THEN v_table := 'str_dome_requests';
    WHEN 'member_support_tickets' THEN v_table := 'member_support_tickets';
    WHEN 'arx_support_tickets' THEN v_table := 'arx_support_tickets'; v_user_col := 'submitted_by';
    ELSE RAISE EXCEPTION 'Deletion not allowed for source: %', p_source;
  END CASE;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_table)
    INTO v_before USING p_id;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  v_user := NULLIF(v_before->>v_user_col, '')::uuid;
  IF v_user IS NOT NULL THEN
    SELECT id INTO v_account FROM public.v2_accounts WHERE user_id = v_user LIMIT 1;
  END IF;

  EXECUTE format('DELETE FROM public.%I WHERE id = $1', v_table) USING p_id;

  INSERT INTO public.v2_admin_actions (
    entity_type, entity_id, account_id, user_id, action, from_status, to_status, notes, actor_id, before_data
  ) VALUES (
    p_source, p_id, v_account, v_user, 'deleted', v_before->>v_status_col, 'deleted',
    COALESCE(NULLIF(trim(p_reason), ''), 'Invalid or duplicate request removed by admin'),
    v_actor, v_before
  );

  RETURN jsonb_build_object('deleted', true, 'id', p_id, 'archived', true);
END;
$$;

REVOKE ALL ON FUNCTION public.v2_admin_delete_request(text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v2_admin_delete_request(text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_admin_delete_request(text, uuid, text) TO service_role;

-- Bulk delete wrapper
CREATE OR REPLACE FUNCTION public.v2_admin_bulk_delete_requests(
  p_source text,
  p_ids uuid[],
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_id uuid;
  v_ok int := 0;
  v_fail int := 0;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'No requests selected';
  END IF;
  IF array_length(p_ids, 1) > 500 THEN
    RAISE EXCEPTION 'Too many requests in one batch (max 500)';
  END IF;

  FOREACH v_id IN ARRAY p_ids LOOP
    BEGIN
      PERFORM public.v2_admin_delete_request(p_source, v_id, p_reason);
      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      v_fail := v_fail + 1;
      v_errors := v_errors || jsonb_build_object('id', v_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('deleted', v_ok, 'failed', v_fail, 'errors', v_errors);
END;
$$;

REVOKE ALL ON FUNCTION public.v2_admin_bulk_delete_requests(text, uuid[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v2_admin_bulk_delete_requests(text, uuid[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_admin_bulk_delete_requests(text, uuid[], text) TO service_role;