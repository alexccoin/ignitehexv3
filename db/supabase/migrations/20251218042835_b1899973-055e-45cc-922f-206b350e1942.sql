-- Fix process_staking_request to use CORRECT APY rates matching update_pool_apy_by_duration
-- This ensures new staking pools get the same APY rates as existing pools

CREATE OR REPLACE FUNCTION public.process_staking_request(
  p_request_id UUID,
  p_action TEXT,
  p_admin_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_apy_rate NUMERIC;
  v_result JSON;
BEGIN
  -- Get the staking request
  SELECT * INTO v_request FROM staking_requests WHERE id = p_request_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Request not found');
  END IF;
  
  IF v_request.status != 'pending' THEN
    RETURN json_build_object('success', false, 'error', 'Request already processed');
  END IF;

  IF p_action = 'approve' THEN
    -- Calculate APY based on pool type and duration (matching update_pool_apy_by_duration)
    v_apy_rate := CASE 
      WHEN v_request.pool_type = 'str' THEN
        CASE 
          WHEN COALESCE(v_request.duration_months, 3) >= 48 THEN 70.0
          WHEN COALESCE(v_request.duration_months, 3) >= 36 THEN 46.0
          WHEN COALESCE(v_request.duration_months, 3) >= 24 THEN 31.5
          WHEN COALESCE(v_request.duration_months, 3) >= 12 THEN 20.0
          WHEN COALESCE(v_request.duration_months, 3) >= 6 THEN 14.75
          ELSE 12.0
        END
      WHEN v_request.pool_type = 'ccos' THEN
        CASE 
          WHEN COALESCE(v_request.duration_months, 3) >= 48 THEN 76.25
          WHEN COALESCE(v_request.duration_months, 3) >= 36 THEN 52.0
          WHEN COALESCE(v_request.duration_months, 3) >= 24 THEN 35.75
          WHEN COALESCE(v_request.duration_months, 3) >= 12 THEN 22.5
          WHEN COALESCE(v_request.duration_months, 3) >= 6 THEN 16.5
          ELSE 13.5
        END
      WHEN v_request.pool_type = 'domain' THEN
        CASE 
          WHEN COALESCE(v_request.duration_months, 3) >= 48 THEN 82.5
          WHEN COALESCE(v_request.duration_months, 3) >= 36 THEN 57.5
          WHEN COALESCE(v_request.duration_months, 3) >= 24 THEN 40.0
          WHEN COALESCE(v_request.duration_months, 3) >= 12 THEN 25.0
          WHEN COALESCE(v_request.duration_months, 3) >= 9 THEN 21.5
          WHEN COALESCE(v_request.duration_months, 3) >= 6 THEN 18.0
          ELSE 18.0
        END
      WHEN v_request.pool_type = 'arss' THEN
        CASE 
          WHEN COALESCE(v_request.duration_months, 3) >= 48 THEN 70.0
          WHEN COALESCE(v_request.duration_months, 3) >= 36 THEN 46.0
          WHEN COALESCE(v_request.duration_months, 3) >= 24 THEN 31.5
          WHEN COALESCE(v_request.duration_months, 3) >= 12 THEN 20.0
          WHEN COALESCE(v_request.duration_months, 3) >= 6 THEN 14.75
          ELSE 12.0
        END
      ELSE 12.0
    END;

    -- Insert a new staking pool entry (allows multiple entries per duration)
    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      staked_amount,
      balance,
      stake_duration_months,
      apy_rate,
      dynamic_apy,
      status,
      start_date,
      end_date,
      lock_end_date,
      rewards_earned,
      last_reward_date,
      created_at,
      updated_at
    ) VALUES (
      v_request.user_id,
      v_request.pool_type,
      v_request.amount,
      v_request.amount,
      COALESCE(v_request.duration_months, 3),
      v_apy_rate,
      v_apy_rate,
      'active',
      NOW(),
      NOW() + (COALESCE(v_request.duration_months, 3) || ' months')::INTERVAL,
      NOW() + (COALESCE(v_request.duration_months, 3) || ' months')::INTERVAL,
      0,
      NULL,
      NOW(),
      NOW()
    );

    -- Update the request status
    UPDATE staking_requests 
    SET status = 'approved', 
        processed_at = NOW(),
        admin_notes = p_admin_notes
    WHERE id = p_request_id;

    RETURN json_build_object('success', true, 'message', 'Staking request approved', 'apy_rate', v_apy_rate);
    
  ELSIF p_action = 'decline' OR p_action = 'reject' THEN
    UPDATE staking_requests 
    SET status = 'declined', 
        processed_at = NOW(),
        admin_notes = p_admin_notes
    WHERE id = p_request_id;

    RETURN json_build_object('success', true, 'message', 'Staking request declined');
  ELSE
    RETURN json_build_object('success', false, 'error', 'Invalid action. Use approve, decline, or reject');
  END IF;
END;
$$;