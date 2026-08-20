-- Fix the process_staking_request function to use INSERT instead of ON CONFLICT
-- since we removed the unique constraints to allow multiple staking entries per duration

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
    -- Calculate APY based on pool type and duration
    v_apy_rate := CASE 
      WHEN v_request.pool_type = 'str' THEN
        CASE v_request.duration_months
          WHEN 3 THEN 5.0
          WHEN 6 THEN 7.5
          WHEN 9 THEN 10.0
          WHEN 12 THEN 12.5
          WHEN 24 THEN 15.0
          WHEN 36 THEN 17.5
          WHEN 48 THEN 20.0
          ELSE 5.0
        END
      WHEN v_request.pool_type = 'ccos' THEN
        CASE v_request.duration_months
          WHEN 3 THEN 6.0
          WHEN 6 THEN 9.0
          WHEN 9 THEN 12.0
          WHEN 12 THEN 15.0
          WHEN 24 THEN 18.0
          WHEN 36 THEN 21.0
          WHEN 48 THEN 24.0
          ELSE 6.0
        END
      WHEN v_request.pool_type = 'domain' THEN
        CASE v_request.duration_months
          WHEN 3 THEN 4.0
          WHEN 6 THEN 6.0
          WHEN 9 THEN 8.0
          WHEN 12 THEN 10.0
          WHEN 24 THEN 12.0
          WHEN 36 THEN 14.0
          WHEN 48 THEN 16.0
          ELSE 4.0
        END
      ELSE 5.0
    END;

    -- Insert a new staking pool entry (no ON CONFLICT - allows multiple entries per duration)
    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      staked_amount,
      stake_duration_months,
      apy_rate,
      status,
      start_date,
      end_date,
      rewards_earned,
      last_reward_date
    ) VALUES (
      v_request.user_id,
      v_request.pool_type,
      v_request.amount,
      COALESCE(v_request.duration_months, 12),
      v_apy_rate,
      'active',
      NOW(),
      NOW() + (COALESCE(v_request.duration_months, 12) || ' months')::INTERVAL,
      0,
      NOW()
    );

    -- Update the request status
    UPDATE staking_requests 
    SET status = 'approved', 
        processed_at = NOW(),
        admin_notes = p_admin_notes
    WHERE id = p_request_id;

    RETURN json_build_object('success', true, 'message', 'Staking request approved');
    
  ELSIF p_action = 'decline' THEN
    UPDATE staking_requests 
    SET status = 'declined', 
        processed_at = NOW(),
        admin_notes = p_admin_notes
    WHERE id = p_request_id;

    RETURN json_build_object('success', true, 'message', 'Staking request declined');
  ELSE
    RETURN json_build_object('success', false, 'error', 'Invalid action');
  END IF;
END;
$$;