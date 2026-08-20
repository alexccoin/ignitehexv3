-- Bulk quarantine / release ---------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_bulk_set_profile_status(
  target_user_ids uuid[],
  new_status text,
  reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  uid uuid;
  prev text;
  n int := 0;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  IF new_status NOT IN ('approved','suspended','pending','closed') THEN
    RAISE EXCEPTION 'Unsupported status %', new_status;
  END IF;

  FOREACH uid IN ARRAY target_user_ids LOOP
    SELECT status::text INTO prev FROM user_profiles WHERE user_id = uid;
    IF prev IS NULL THEN CONTINUE; END IF;

    UPDATE user_profiles
    SET status = new_status::account_status,
        account_status = new_status,
        updated_at = now()
    WHERE user_id = uid;

    INSERT INTO v2_admin_actions (entity_type, entity_id, user_id, action, from_status, to_status, notes, actor_id)
    VALUES ('risk_quarantine', uid, uid,
            CASE WHEN new_status = 'suspended' THEN 'quarantine' ELSE 'release' END,
            prev, new_status, reason, auth.uid());
    n := n + 1;
  END LOOP;

  RETURN jsonb_build_object('updated', n, 'status', new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bulk_set_profile_status(uuid[], text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_bulk_set_profile_status(uuid[], text, text) TO authenticated;

-- Correct unbacked positions ---------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_correct_unbacked_positions(
  target_user_id uuid,
  scale numeric,
  reason text DEFAULT NULL,
  dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_action uuid;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  IF scale IS NULL OR scale < 0 OR scale > 1 THEN
    RAISE EXCEPTION 'scale must be between 0 and 1';
  END IF;

  SELECT jsonb_build_object(
    'staking', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'pool_type', pool_type, 'balance', balance,
        'staked_amount', staked_amount, 'rewards_earned', rewards_earned))
      FROM user_staking_pools WHERE user_id = target_user_id), '[]'::jsonb),
    'shares', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'balance', balance, 'locked_balance', locked_balance, 'wnft_shares', wnft_shares))
      FROM user_str_shares WHERE user_id = target_user_id), '[]'::jsonb),
    'vesting', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'token_type', token_type, 'amount', amount))
      FROM vesting_tokens WHERE user_id = target_user_id), '[]'::jsonb)
  ) INTO v_before;

  IF dry_run THEN
    RETURN jsonb_build_object('dry_run', true, 'scale', scale, 'before', v_before);
  END IF;

  UPDATE user_staking_pools
  SET balance = ROUND(COALESCE(balance,0) * scale, 8),
      staked_amount = ROUND(COALESCE(staked_amount,0) * scale, 8),
      rewards_earned = ROUND(COALESCE(rewards_earned,0) * scale, 8),
      updated_at = now()
  WHERE user_id = target_user_id;

  UPDATE user_str_shares
  SET balance = ROUND(COALESCE(balance,0) * scale, 8),
      locked_balance = ROUND(COALESCE(locked_balance,0) * scale, 8),
      wnft_shares = ROUND(COALESCE(wnft_shares,0) * scale, 8),
      updated_at = now()
  WHERE user_id = target_user_id;

  UPDATE vesting_tokens
  SET amount = ROUND(COALESCE(amount,0) * scale, 8),
      updated_at = now()
  WHERE user_id = target_user_id;

  SELECT jsonb_build_object(
    'staking', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'pool_type', pool_type, 'balance', balance,
        'staked_amount', staked_amount, 'rewards_earned', rewards_earned))
      FROM user_staking_pools WHERE user_id = target_user_id), '[]'::jsonb),
    'shares', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'balance', balance, 'locked_balance', locked_balance, 'wnft_shares', wnft_shares))
      FROM user_str_shares WHERE user_id = target_user_id), '[]'::jsonb),
    'vesting', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'token_type', token_type, 'amount', amount))
      FROM vesting_tokens WHERE user_id = target_user_id), '[]'::jsonb)
  ) INTO v_after;

  INSERT INTO v2_admin_actions (entity_type, entity_id, user_id, action, from_status, to_status, notes, actor_id, before_data, after_data)
  VALUES ('position_correction', target_user_id, target_user_id, 'correct_unbacked',
          'unbacked', 'scaled_to_admin_credit',
          COALESCE(reason, 'Positions scaled to admin-credited value') || ' (scale ' || scale::text || ')',
          auth.uid(), v_before, v_after)
  RETURNING id INTO v_action;

  RETURN jsonb_build_object('dry_run', false, 'scale', scale, 'action_id', v_action, 'before', v_before, 'after', v_after);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_correct_unbacked_positions(uuid, numeric, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_correct_unbacked_positions(uuid, numeric, text, boolean) TO authenticated;

-- Undo a correction --------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_revert_position_correction(action_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  rec record;
  item jsonb;
  n int := 0;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  SELECT * INTO rec FROM v2_admin_actions
  WHERE id = action_id AND entity_type = 'position_correction';
  IF rec IS NULL THEN
    RAISE EXCEPTION 'Correction record not found';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(rec.before_data->'staking') LOOP
    UPDATE user_staking_pools
    SET balance = (item->>'balance')::numeric,
        staked_amount = (item->>'staked_amount')::numeric,
        rewards_earned = (item->>'rewards_earned')::numeric,
        updated_at = now()
    WHERE id = (item->>'id')::uuid;
    n := n + 1;
  END LOOP;

  FOR item IN SELECT * FROM jsonb_array_elements(rec.before_data->'shares') LOOP
    UPDATE user_str_shares
    SET balance = (item->>'balance')::numeric,
        locked_balance = (item->>'locked_balance')::numeric,
        wnft_shares = (item->>'wnft_shares')::numeric,
        updated_at = now()
    WHERE id = (item->>'id')::uuid;
    n := n + 1;
  END LOOP;

  FOR item IN SELECT * FROM jsonb_array_elements(rec.before_data->'vesting') LOOP
    UPDATE vesting_tokens
    SET amount = (item->>'amount')::numeric, updated_at = now()
    WHERE id = (item->>'id')::uuid;
    n := n + 1;
  END LOOP;

  INSERT INTO v2_admin_actions (entity_type, entity_id, user_id, action, from_status, to_status, notes, actor_id, before_data, after_data)
  VALUES ('position_correction', rec.user_id, rec.user_id, 'revert_correction',
          'scaled_to_admin_credit', 'restored', 'Reverted correction ' || action_id::text,
          auth.uid(), rec.after_data, rec.before_data);

  RETURN jsonb_build_object('restored_rows', n);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_revert_position_correction(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_revert_position_correction(uuid) TO authenticated;