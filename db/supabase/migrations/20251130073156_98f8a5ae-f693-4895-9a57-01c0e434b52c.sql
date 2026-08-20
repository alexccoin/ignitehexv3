-- Fix process_staking_request to set proper APY rates on pool creation
-- Currently new pools are created with apy_rate = 0, causing zero rewards

CREATE OR REPLACE FUNCTION public.process_staking_request(
  request_id uuid, 
  approve boolean, 
  admin_notes_param text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  request_record RECORD;
  result jsonb;
  admin_user_id uuid;
  target_pool_id uuid;
  target_lock_end timestamptz;
  calculated_apy NUMERIC;
BEGIN
  admin_user_id := auth.uid();
  IF NOT is_admin(admin_user_id) THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;

  -- Fetch the request with duration_months column
  SELECT * INTO request_record
  FROM staking_requests
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Staking request not found or already processed');
  END IF;

  IF approve THEN
    IF request_record.request_type = 'stake' THEN
      -- Calculate the correct APY based on token type and duration
      calculated_apy := CASE
        WHEN request_record.pool_type = 'str' THEN
          CASE
            WHEN request_record.duration_months >= 48 THEN 70.0
            WHEN request_record.duration_months >= 36 THEN 46.0
            WHEN request_record.duration_months >= 24 THEN 31.5
            WHEN request_record.duration_months >= 12 THEN 20.0
            WHEN request_record.duration_months >= 6 THEN 14.75
            ELSE 12.0
          END
        WHEN request_record.pool_type = 'ccos' THEN
          CASE
            WHEN request_record.duration_months >= 48 THEN 76.25
            WHEN request_record.duration_months >= 36 THEN 52.0
            WHEN request_record.duration_months >= 24 THEN 35.75
            WHEN request_record.duration_months >= 12 THEN 22.5
            WHEN request_record.duration_months >= 6 THEN 16.5
            ELSE 13.5
          END
        WHEN request_record.pool_type = 'domain' THEN
          CASE
            WHEN request_record.duration_months >= 48 THEN 82.5
            WHEN request_record.duration_months >= 36 THEN 57.5
            WHEN request_record.duration_months >= 24 THEN 40.0
            WHEN request_record.duration_months >= 12 THEN 25.0
            WHEN request_record.duration_months >= 9 THEN 21.5
            WHEN request_record.duration_months >= 6 THEN 18.0
            ELSE 18.0
          END
        ELSE 12.0
      END;

      BEGIN
        -- Use distribute_enhanced_rewards to create the staking pool
        SELECT * INTO result FROM distribute_enhanced_rewards(
          user_id_param := request_record.user_id,
          token_type_param := request_record.pool_type,
          amount := request_record.amount,
          duration_months_param := request_record.duration_months,
          network_efficiency_param := 1.0
        );
      EXCEPTION WHEN unique_violation THEN
        -- If unique violation, create a NEW separate pool instead of merging
        SELECT esp.id INTO target_pool_id
        FROM enhanced_staking_pools esp
        WHERE esp.token_type = request_record.pool_type
          AND esp.duration_months = request_record.duration_months
          AND esp.status = 'active'
        ORDER BY esp.created_at DESC
        LIMIT 1;

        target_lock_end := now() + (request_record.duration_months || ' months')::interval;

        -- INSERT with correct APY instead of 0
        INSERT INTO user_staking_pools (
          user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate,
          stake_duration_months, lock_end_date, is_enhanced_pool, enhanced_pool_id, 
          created_at, updated_at, status, dynamic_apy
        ) VALUES (
          request_record.user_id, 
          request_record.pool_type, 
          request_record.amount, 
          request_record.amount, 
          0, 
          calculated_apy,  -- Use calculated APY instead of 0
          request_record.duration_months, 
          target_lock_end, 
          true, 
          target_pool_id, 
          now(), 
          now(),
          'active',
          calculated_apy  -- Also set dynamic_apy
        );

        result := jsonb_build_object('success', true, 'created_new_pool', true);
      END;

      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        approved_by = admin_user_id,
        admin_notes = COALESCE(admin_notes_param, 'Approved and processed')
      WHERE id = request_id;

    ELSIF request_record.request_type = 'unstake' THEN
      -- Unstake from pools matching the duration
      UPDATE user_staking_pools
      SET 
        staked_amount = GREATEST(0, staked_amount - request_record.amount),
        balance = GREATEST(0, balance - request_record.amount),
        updated_at = now()
      WHERE user_id = request_record.user_id 
        AND pool_type = request_record.pool_type
        AND stake_duration_months = request_record.duration_months
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

  -- Best-effort audit log
  BEGIN
    INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      admin_user_id,
      CASE WHEN approve THEN 'approve_staking_request' ELSE 'reject_staking_request' END,
      'staking_request',
      request_id,
      jsonb_build_object(
        'request_type', request_record.request_type,
        'pool_type', request_record.pool_type,
        'amount', request_record.amount,
        'duration_months', request_record.duration_months,
        'calculated_apy', calculated_apy
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'approved', approve);
END;
$function$;