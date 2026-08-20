-- Create comprehensive function to fix all enhanced pool assignments based on original user selections
CREATE OR REPLACE FUNCTION fix_enhanced_pools_based_on_original_selections()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  user_record RECORD;
  target_pool enhanced_staking_pools%ROWTYPE;
  original_duration INTEGER;
  corrections_applied INTEGER := 0;
  corrections_summary jsonb := '[]'::jsonb;
  correction_record jsonb;
BEGIN
  -- Log the start of comprehensive fixes
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'comprehensive_enhanced_pool_fix_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  -- Loop through all users with enhanced staking pools
  FOR user_record IN
    SELECT DISTINCT
      usp.user_id,
      usp.pool_type,
      usp.staked_amount,
      usp.balance,
      usp.rewards_earned,
      usp.stake_duration_months,
      usp.enhanced_pool_id,
      usp.dynamic_apy,
      usp.apy_rate,
      -- Get the original duration from the latest approved staking request
      COALESCE(
        (SELECT 
          CASE 
            WHEN sr.description ~ 'Lock Period: (\d+) months' THEN 
              (regexp_match(sr.description, 'Lock Period: (\d+) months'))[1]::INTEGER
            WHEN sr.description ~ '(\d+) months?' THEN 
              (regexp_match(sr.description, '(\d+) months?'))[1]::INTEGER
            WHEN sr.description ~ '6 month' THEN 6
            WHEN sr.description ~ '1 year' THEN 12
            WHEN sr.description ~ '2 year' THEN 24
            WHEN sr.description ~ '3 year' THEN 36
            WHEN sr.description ~ '4 year' THEN 48
            -- Fallback logic based on staked amount
            WHEN usp.staked_amount >= 500000 THEN 48
            WHEN usp.staked_amount >= 200000 THEN 24
            WHEN usp.staked_amount >= 100000 THEN 12
            WHEN usp.staked_amount >= 50000 THEN 6
            ELSE 3
          END
        FROM staking_requests sr 
        WHERE sr.user_id = usp.user_id 
        AND sr.pool_type = usp.pool_type
        AND sr.status = 'approved'
        AND sr.request_type = 'stake'
        ORDER BY sr.processed_at DESC 
        LIMIT 1),
        -- Final fallback based on amount
        CASE 
          WHEN usp.staked_amount >= 500000 THEN 48
          WHEN usp.staked_amount >= 200000 THEN 24
          WHEN usp.staked_amount >= 100000 THEN 12
          WHEN usp.staked_amount >= 50000 THEN 6
          ELSE 3
        END
      ) as original_duration_months
    FROM user_staking_pools usp
    WHERE usp.is_enhanced_pool = true 
    AND usp.staked_amount > 0
  LOOP
    original_duration := user_record.original_duration_months;
    
    -- Find the correct enhanced pool for this duration and token type
    SELECT * INTO target_pool
    FROM enhanced_staking_pools
    WHERE duration_months = original_duration
    AND token_type = user_record.pool_type
    AND status = 'active'
    LIMIT 1;
    
    -- If no exact match, find the closest duration pool
    IF NOT FOUND THEN
      SELECT * INTO target_pool
      FROM enhanced_staking_pools
      WHERE token_type = user_record.pool_type
      AND status = 'active'
      ORDER BY ABS(duration_months - original_duration)
      LIMIT 1;
    END IF;
    
    -- Skip if no suitable pool found
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    
    -- Check if correction is needed
    IF user_record.enhanced_pool_id != target_pool.id OR 
       ABS(user_record.dynamic_apy - target_pool.apr_max) > 0.5 OR
       ABS(user_record.apy_rate - target_pool.apr_max) > 0.5 OR
       user_record.stake_duration_months != target_pool.duration_months THEN
      
      -- Update the user's pool with correct values
      UPDATE user_staking_pools
      SET 
        enhanced_pool_id = target_pool.id,
        stake_duration_months = target_pool.duration_months,
        dynamic_apy = target_pool.apr_max,
        apy_rate = target_pool.apr_max,
        lock_end_date = now() + (target_pool.duration_months || ' months')::interval,
        updated_at = now()
      WHERE user_id = user_record.user_id 
      AND pool_type = user_record.pool_type;
      
      -- Track this correction
      correction_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'pool_type', user_record.pool_type,
        'staked_amount', user_record.staked_amount,
        'original_duration_selected', original_duration,
        'previous_pool_id', user_record.enhanced_pool_id,
        'corrected_pool_id', target_pool.id,
        'previous_apy', user_record.dynamic_apy,
        'corrected_apy', target_pool.apr_max,
        'previous_duration', user_record.stake_duration_months,
        'corrected_duration', target_pool.duration_months,
        'pool_name', target_pool.name
      );
      
      corrections_summary := corrections_summary || correction_record;
      corrections_applied := corrections_applied + 1;
    END IF;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'comprehensive_enhanced_pool_fix_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'corrections_applied', corrections_applied,
      'corrections_summary', corrections_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'corrections_applied', corrections_applied,
    'corrections_summary', corrections_summary,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'comprehensive_enhanced_pool_fix_failed', 
    'user_staking_pools',
    jsonb_build_object(
      'error', SQLERRM,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'timestamp', now()
  );
END;
$$;