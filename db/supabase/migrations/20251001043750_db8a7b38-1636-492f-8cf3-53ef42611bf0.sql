-- Fix initialize_user_staking_pools to work with multi-duration pools
CREATE OR REPLACE FUNCTION public.initialize_user_staking_pools(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Insert default 3-month pools for STR, CCOS, and Domain if they don't exist
  -- Use the new unique constraint (user_id, pool_type, stake_duration_months)
  INSERT INTO user_staking_pools (
    user_id, 
    pool_type, 
    balance, 
    staked_amount,
    apy_rate, 
    stake_duration_months,
    is_enhanced_pool,
    lock_end_date
  )
  VALUES 
    (target_user_id, 'str', 0, 0, 11.0, 3, false, now() + interval '3 months'),
    (target_user_id, 'ccos', 0, 0, 11.0, 3, false, now() + interval '3 months'),
    (target_user_id, 'domain', 0, 0, 11.0, 3, false, now() + interval '3 months')
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
END;
$$;

-- Fix process_staking_request to handle multi-duration pools
CREATE OR REPLACE FUNCTION public.process_staking_request(
  request_id uuid,
  approve boolean,
  admin_notes text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  request_data staking_requests%ROWTYPE;
  duration_months INTEGER;
  target_pool_id UUID;
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Get the request data
  SELECT * INTO request_data 
  FROM staking_requests 
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Extract duration from description (format: "... | Lock Period: X months")
  IF request_data.description ~ 'Lock Period: (\d+) months' THEN
    duration_months := (regexp_match(request_data.description, 'Lock Period: (\d+) months'))[1]::INTEGER;
  ELSE
    -- Default to 3 months if not specified
    duration_months := 3;
  END IF;

  -- Update request status
  UPDATE staking_requests 
  SET 
    status = CASE WHEN approve THEN 'approved' ELSE 'rejected' END,
    admin_notes = process_staking_request.admin_notes,
    approved_by = auth.uid(),
    processed_at = now(),
    updated_at = now()
  WHERE id = request_id;

  -- If approved, create or update the specific duration pool
  IF approve THEN
    -- Try to find existing pool for this user/token/duration
    SELECT id INTO target_pool_id
    FROM user_staking_pools
    WHERE user_id = request_data.user_id 
      AND pool_type = request_data.pool_type
      AND stake_duration_months = duration_months;

    IF target_pool_id IS NULL THEN
      -- Create new pool with the specified duration
      INSERT INTO user_staking_pools (
        user_id,
        pool_type,
        balance,
        staked_amount,
        apy_rate,
        dynamic_apy,
        stake_duration_months,
        is_enhanced_pool,
        lock_end_date
      ) VALUES (
        request_data.user_id,
        request_data.pool_type,
        CASE WHEN request_data.request_type = 'stake' THEN request_data.amount ELSE 0 END,
        CASE WHEN request_data.request_type = 'stake' THEN request_data.amount ELSE 0 END,
        CASE duration_months
          WHEN 3 THEN 11.0
          WHEN 6 THEN 13.0
          WHEN 12 THEN 15.0
          WHEN 24 THEN 18.0
          WHEN 36 THEN 22.0
          WHEN 48 THEN 25.0
          ELSE 11.0
        END,
        CASE duration_months
          WHEN 3 THEN 11.0
          WHEN 6 THEN 13.0
          WHEN 12 THEN 15.0
          WHEN 24 THEN 18.0
          WHEN 36 THEN 22.0
          WHEN 48 THEN 25.0
          ELSE 11.0
        END,
        duration_months,
        false,
        now() + (duration_months || ' months')::interval
      )
      RETURNING id INTO target_pool_id;
    ELSE
      -- Update existing pool for this specific duration
      IF request_data.request_type = 'stake' THEN
        UPDATE user_staking_pools 
        SET 
          balance = balance + request_data.amount,
          staked_amount = staked_amount + request_data.amount,
          updated_at = now()
        WHERE id = target_pool_id;
      ELSIF request_data.request_type = 'unstake' THEN
        UPDATE user_staking_pools 
        SET 
          balance = GREATEST(0, balance - request_data.amount),
          staked_amount = GREATEST(0, staked_amount - request_data.amount),
          updated_at = now()
        WHERE id = target_pool_id;
      END IF;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;