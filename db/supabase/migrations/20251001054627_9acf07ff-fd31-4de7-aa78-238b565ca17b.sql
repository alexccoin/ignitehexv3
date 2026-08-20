-- Remove unique constraint to allow multiple pools at same duration
-- Then redistribute pools based on individual staking requests

-- Step 1: Drop the unique constraint
ALTER TABLE user_staking_pools 
DROP CONSTRAINT IF EXISTS user_staking_pools_unique_duration;

-- Step 2: Redistribute pools based on staking requests
DO $$
DECLARE
  request_record RECORD;
  existing_pool_count INTEGER;
  correct_pool_id UUID;
  correct_apy NUMERIC;
  pools_created INTEGER := 0;
  pools_updated INTEGER := 0;
BEGIN
  -- Log the start
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    NULL,
    'staking_pool_redistribution_v2_started',
    'user_staking_pools',
    jsonb_build_object(
      'timestamp', now(),
      'description', 'Redistributing pools - allowing multiple pools per duration'
    )
  );

  -- Clear existing pools to start fresh
  DELETE FROM user_staking_pools WHERE staked_amount >= 0;

  -- Process each approved staking request
  FOR request_record IN
    SELECT 
      sr.id as request_id,
      sr.user_id,
      sr.pool_type,
      sr.amount,
      sr.created_at as request_date,
      sr.processed_at,
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
        WHEN sr.amount >= 500000 THEN 48
        WHEN sr.amount >= 200000 THEN 24
        WHEN sr.amount >= 100000 THEN 12
        WHEN sr.amount >= 50000 THEN 6
        ELSE 3
      END as duration_months
    FROM staking_requests sr
    WHERE sr.status = 'approved'
    AND sr.request_type = 'stake'
    AND sr.amount > 0
    ORDER BY sr.user_id, sr.pool_type, sr.created_at
  LOOP
    -- Determine correct APY based on duration
    correct_apy := CASE request_record.duration_months
      WHEN 3 THEN 11.0
      WHEN 6 THEN 13.0
      WHEN 9 THEN 14.0
      WHEN 12 THEN 15.0
      WHEN 24 THEN 18.0
      WHEN 36 THEN 22.0
      WHEN 48 THEN 25.0
      ELSE 11.0
    END;

    -- Find corresponding enhanced pool
    SELECT id INTO correct_pool_id
    FROM enhanced_staking_pools
    WHERE duration_months = request_record.duration_months
    AND token_type = request_record.pool_type
    AND status = 'active'
    LIMIT 1;

    -- Create new pool for each request
    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      balance,
      staked_amount,
      rewards_earned,
      apy_rate,
      dynamic_apy,
      stake_duration_months,
      lock_end_date,
      is_enhanced_pool,
      enhanced_pool_id,
      original_stake_amount,
      created_at,
      updated_at,
      last_reward_date
    ) VALUES (
      request_record.user_id,
      request_record.pool_type,
      request_record.amount,
      request_record.amount,
      0,
      correct_apy,
      correct_apy,
      request_record.duration_months,
      COALESCE(request_record.processed_at, request_record.request_date) + (request_record.duration_months || ' months')::interval,
      true,
      correct_pool_id,
      request_record.amount,
      request_record.request_date,
      now(),
      COALESCE(request_record.processed_at, request_record.request_date)
    );
    
    pools_created := pools_created + 1;
  END LOOP;

  -- Log completion
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    NULL,
    'staking_pool_redistribution_v2_completed',
    'user_staking_pools',
    jsonb_build_object(
      'pools_created', pools_created,
      'timestamp', now(),
      'status', 'success'
    )
  );

  RAISE NOTICE 'Pool redistribution completed. Created: % pools', pools_created;
END $$;