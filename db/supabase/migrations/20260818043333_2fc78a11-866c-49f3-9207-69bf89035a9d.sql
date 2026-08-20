-- 1. Threaded admin <-> member communication on requests
CREATE TABLE IF NOT EXISTS public.v2_request_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL,
  request_id uuid NOT NULL,
  user_id uuid,
  sender_role text NOT NULL CHECK (sender_role IN ('admin','member')),
  sender_id uuid,
  body text NOT NULL,
  requires_response boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT ON public.v2_request_messages TO authenticated;
GRANT ALL ON public.v2_request_messages TO service_role;

ALTER TABLE public.v2_request_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage request messages" ON public.v2_request_messages;
CREATE POLICY "Admins manage request messages"
  ON public.v2_request_messages FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

DROP POLICY IF EXISTS "Members read their request messages" ON public.v2_request_messages;
CREATE POLICY "Members read their request messages"
  ON public.v2_request_messages FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Members reply on their request messages" ON public.v2_request_messages;
CREATE POLICY "Members reply on their request messages"
  ON public.v2_request_messages FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND sender_role = 'member' AND sender_id = auth.uid());

CREATE INDEX IF NOT EXISTS v2_request_messages_thread_idx
  ON public.v2_request_messages (source, request_id, created_at);

-- 2. Extend the admin status RPC: configurable status column + profile update sources
CREATE OR REPLACE FUNCTION public.v2_admin_update_request(
  p_source text,
  p_id uuid,
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
  v_table text;
  v_notes_col text;
  v_actor_col text;
  v_time_col text;
  v_user_col text := 'user_id';
  v_status_col text := 'status';
  v_before jsonb;
  v_after jsonb;
  v_from text;
  v_user uuid;
  v_account uuid;
  v_sql text;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  IF p_status IS NULL OR length(trim(p_status)) = 0 OR length(p_status) > 40 THEN
    RAISE EXCEPTION 'Invalid status';
  END IF;

  CASE p_source
    WHEN 'member_support_tickets' THEN
      v_table := 'member_support_tickets'; v_notes_col := 'admin_notes'; v_actor_col := 'resolved_by'; v_time_col := 'resolved_at';
    WHEN 'arx_support_tickets' THEN
      v_table := 'arx_support_tickets'; v_actor_col := 'assigned_to'; v_time_col := 'resolved_at'; v_user_col := 'submitted_by';
    WHEN 'missing_asset_reports' THEN
      v_table := 'missing_asset_reports'; v_notes_col := 'admin_notes'; v_actor_col := 'reviewed_by'; v_time_col := 'reviewed_at';
    WHEN 'pending_profile_changes' THEN
      v_table := 'pending_profile_changes'; v_notes_col := 'admin_notes'; v_actor_col := 'reviewed_by'; v_time_col := 'reviewed_at';
    WHEN 'user_profiles_updated' THEN
      v_table := 'user_profiles_updated'; v_status_col := 'submission_status'; v_notes_col := 'admin_notes'; v_actor_col := 'reviewed_by'; v_time_col := 'reviewed_at';
    WHEN 'staking_requests' THEN
      v_table := 'staking_requests'; v_notes_col := 'admin_notes'; v_actor_col := 'approved_by'; v_time_col := 'processed_at';
    WHEN 'str_dome_requests' THEN
      v_table := 'str_dome_requests'; v_notes_col := 'admin_notes'; v_actor_col := 'reviewed_by'; v_time_col := 'reviewed_at';
    WHEN 'withdrawal_requests' THEN
      v_table := 'withdrawal_requests'; v_time_col := 'processed_at';
    WHEN 'ipo_listing_requests' THEN
      v_table := 'ipo_listing_requests'; v_notes_col := 'admin_notes'; v_time_col := 'processed_at';
    ELSE
      RAISE EXCEPTION 'Unsupported request source: %', p_source;
  END CASE;

  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.id = $1', v_table)
    INTO v_before USING p_id;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  v_from := v_before->>v_status_col;
  v_user := NULLIF(v_before->>v_user_col, '')::uuid;

  v_sql := format('UPDATE public.%I SET %I = $1', v_table, v_status_col);
  IF v_notes_col IS NOT NULL THEN
    v_sql := v_sql || format(', %I = COALESCE($2, %I)', v_notes_col, v_notes_col);
  END IF;
  IF v_actor_col IS NOT NULL THEN
    v_sql := v_sql || format(', %I = $3', v_actor_col);
  END IF;
  IF v_time_col IS NOT NULL THEN
    v_sql := v_sql || format(', %I = now()', v_time_col);
  END IF;
  v_sql := v_sql || ' WHERE id = $4 RETURNING to_jsonb(' || quote_ident(v_table) || ')';

  EXECUTE 'WITH upd AS (' || v_sql || ') SELECT * FROM upd'
    INTO v_after USING p_status, p_notes, v_actor, p_id;

  IF v_user IS NOT NULL THEN
    SELECT id INTO v_account FROM public.v2_accounts WHERE user_id = v_user LIMIT 1;
  END IF;

  INSERT INTO public.v2_admin_actions (
    entity_type, entity_id, account_id, user_id, action, from_status, to_status, notes, actor_id, before_data, after_data
  ) VALUES (
    p_source, p_id, v_account, v_user, 'status_change', v_from, p_status, p_notes, v_actor, v_before, v_after
  );

  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.v2_admin_update_request(text, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v2_admin_update_request(text, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_admin_update_request(text, uuid, text, text) TO service_role;

-- 3. Admin message / information request on a queue item
CREATE OR REPLACE FUNCTION public.v2_admin_message_request(
  p_source text,
  p_id uuid,
  p_user_id uuid,
  p_body text,
  p_requires_response boolean DEFAULT true,
  p_subject text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_msg public.v2_request_messages;
  v_account uuid;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RAISE EXCEPTION 'Message body required';
  END IF;

  INSERT INTO public.v2_request_messages (source, request_id, user_id, sender_role, sender_id, body, requires_response)
  VALUES (p_source, p_id, p_user_id, 'admin', v_actor, trim(p_body), COALESCE(p_requires_response, true))
  RETURNING * INTO v_msg;

  IF p_user_id IS NOT NULL THEN
    INSERT INTO public.user_messages (recipient_id, sender_id, subject, message, message_type)
    VALUES (
      p_user_id,
      v_actor,
      COALESCE(NULLIF(trim(p_subject), ''), 'Information requested on your request'),
      trim(p_body),
      'admin_request'
    );

    SELECT id INTO v_account FROM public.v2_accounts WHERE user_id = p_user_id LIMIT 1;
  END IF;

  INSERT INTO public.v2_admin_actions (
    entity_type, entity_id, account_id, user_id, action, from_status, to_status, notes, actor_id, after_data
  ) VALUES (
    p_source, p_id, v_account, p_user_id, 'admin_message', NULL, NULL, trim(p_body), v_actor, to_jsonb(v_msg)
  );

  RETURN to_jsonb(v_msg);
END;
$$;

REVOKE ALL ON FUNCTION public.v2_admin_message_request(text, uuid, uuid, text, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.v2_admin_message_request(text, uuid, uuid, text, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.v2_admin_message_request(text, uuid, uuid, text, boolean, text) TO service_role;