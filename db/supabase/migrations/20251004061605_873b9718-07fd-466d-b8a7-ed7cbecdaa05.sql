-- Resolve ambiguous "duration_months" by using a distinct local variable and qualifying columns
DROP FUNCTION IF EXISTS public.process_staking_request(uuid, boolean, text);

CREATE FUNCTION public.process_staking_request(
  request_id uuid,
  approve boolean,
  admin_notes_param text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  request_record RECORD;
  result jsonb;
  v_duration_months INTEGER;
  admin_user_id uuid;
  target_pool_id uuid;
  target_lock_end timestamptz;
BEGIN
  admin_user_id := auth.uid();
  IF NOT is_admin(admin_user_id) THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;

  SELECT * INTO request_record
  FROM staking_requests
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Staking request not found or already processed');
  END IF;

  IF approve THEN
    BEGIN
      SELECT (regexp_match(coalesce(request_record.description,''), 'Lock Period: (\d+) months'))[1]::INTEGER
      INTO v_duration_months;
      IF v_duration_months IS NULL THEN v_duration_months := 3; END IF;
    EXCEPTION WHEN OTHERS THEN
      v_duration_months := 3;
    END;

    IF request_record.request_type = 'stake' THEN
      BEGIN
        SELECT * INTO result FROM distribute_enhanced_rewards(
          user_id_param := request_record.user_id,
          token_type_param := request_record.pool_type,
          amount := request_record.amount,
          duration_months_param := v_duration_months,
          network_efficiency_param := 1.0
        );
      EXCEPTION WHEN unique_violation THEN
        -- Fallback: upsert into the existing duration pool to avoid duplicate key errors
        SELECT esp.id INTO target_pool_id
        FROM enhanced_staking_pools esp
        WHERE esp.token_type = request_record.pool_type
          AND esp.duration_months = v_duration_months
          AND esp.status = 'active'
        ORDER BY esp.created_at DESC
        LIMIT 1;

        target_lock_end := now() + (v_duration_months || ' months')::interval;

        INSERT INTO user_staking_pools (
          user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate,
          stake_duration_months, lock_end_date, is_enhanced_pool, enhanced_pool_id, created_at, updated_at
        ) VALUES (
          request_record.user_id, request_record.pool_type, request_record.amount, request_record.amount, 0, 0,
          v_duration_months, target_lock_end, true, target_pool_id, now(), now()
        )
        ON CONFLICT (user_id, pool_type, stake_duration_months)
        DO UPDATE SET 
          balance = user_staking_pools.balance + EXCLUDED.balance,
          staked_amount = user_staking_pools.staked_amount + EXCLUDED.staked_amount,
          enhanced_pool_id = COALESCE(user_staking_pools.enhanced_pool_id, EXCLUDED.enhanced_pool_id),
          is_enhanced_pool = true,
          lock_end_date = GREATEST(user_staking_pools.lock_end_date, EXCLUDED.lock_end_date),
          updated_at = now();

        result := jsonb_build_object('success', true, 'upserted', true);
      END;

      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        approved_by = admin_user_id,
        admin_notes = COALESCE(admin_notes_param, 'Approved and processed')
      WHERE id = request_id;

    ELSIF request_record.request_type = 'unstake' THEN
      UPDATE user_staking_pools
      SET 
        staked_amount = GREATEST(0, staked_amount - request_record.amount),
        balance = GREATEST(0, balance - request_record.amount),
        updated_at = now()
      WHERE user_id = request_record.user_id 
        AND pool_type = request_record.pool_type
        AND staked_amount >= request_record.amount;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient staked balance for unstaking';
      END IF;

      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        approved_by = admin_user_id,
        admin_notes = COALESCE(admin_notes_param, 'Unstake approved')
      WHERE id = request_id;
    END IF;
  ELSE
    UPDATE staking_requests
    SET 
      status = 'rejected',
      processed_at = now(),
      approved_by = admin_user_id,
      admin_notes = COALESCE(admin_notes_param, 'Rejected by admin')
    WHERE id = request_id;
  END IF;

  -- Best-effort audit log (never fail main op)
  BEGIN
    INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      admin_user_id,
      CASE WHEN approve THEN 'staking_request_approved' ELSE 'staking_request_rejected' END,
      'staking_requests', request_id::text,
      jsonb_build_object('target_user', request_record.user_id, 'pool_type', request_record.pool_type,
                         'request_type', request_record.request_type, 'amount', request_record.amount,
                         'admin_notes', admin_notes_param)
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('success', true);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;