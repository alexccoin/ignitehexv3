CREATE OR REPLACE FUNCTION public.v2_apply_profile_update(p_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r public.user_profiles_updated%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.user_profiles_updated WHERE id = p_id;
  IF NOT FOUND OR r.user_id IS NULL THEN RETURN; END IF;

  IF lower(p_status) = 'approved' THEN
    UPDATE public.user_profiles p
    SET full_name = COALESCE(NULLIF(trim(r.full_name), ''), p.full_name),
        email_address = COALESCE(NULLIF(trim(r.email_address), ''), p.email_address),
        address = COALESCE(NULLIF(trim(r.address), ''), p.address),
        city = COALESCE(NULLIF(trim(r.city), ''), p.city),
        country = COALESCE(NULLIF(trim(r.country), ''), p.country),
        postal_code = COALESCE(NULLIF(trim(r.postal_code), ''), p.postal_code),
        str_domain_owned = COALESCE(NULLIF(trim(r.str_domain_owned), ''), p.str_domain_owned),
        bsc_wallet_address = COALESCE(NULLIF(trim(r.bsc_wallet_address), ''), p.bsc_wallet_address),
        btc_wallet_address = COALESCE(NULLIF(trim(r.btc_wallet_address), ''), p.btc_wallet_address),
        account_status = 'approved',
        profile_update_status = 'approved',
        suspended_at = NULL,
        suspension_reason = NULL,
        updated_at = now()
    WHERE p.user_id = r.user_id;
  ELSIF lower(p_status) = 'suspended' THEN
    UPDATE public.user_profiles p
    SET account_status = 'suspended',
        profile_update_status = 'suspended',
        suspended_at = now(),
        suspension_reason = COALESCE(NULLIF(trim(r.admin_notes), ''), 'MiCA profile update suspended by compliance'),
        updated_at = now()
    WHERE p.user_id = r.user_id;
  ELSIF lower(p_status) IN ('rejected', 'declined') THEN
    UPDATE public.user_profiles p
    SET profile_update_status = 'rejected',
        updated_at = now()
    WHERE p.user_id = r.user_id;
  ELSE
    UPDATE public.user_profiles p
    SET profile_update_status = lower(p_status),
        updated_at = now()
    WHERE p.user_id = r.user_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.v2_admin_update_request(p_source text, p_id uuid, p_status text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  IF p_source = 'user_profiles_updated' THEN
    PERFORM public.v2_apply_profile_update(p_id, p_status);
  END IF;

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
$function$;

REVOKE ALL ON FUNCTION public.v2_apply_profile_update(uuid, text) FROM PUBLIC, anon, authenticated;