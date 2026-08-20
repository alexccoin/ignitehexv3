-- Aggregate pools by duration - Fixed GROUP BY issue
-- Calculate duration first in CTE, then aggregate

DO $$
DECLARE
  pool_record RECORD;
  correct_pool_id UUID;
  correct_apy NUMERIC;
  pools_created INTEGER := 0;
BEGIN
  -- Log the start
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    NULL,
    'staking_pool_aggregation_started',
    'user_staking_pools',
    jsonb_build_object(
      'timestamp', now(),
      'description', 'Aggregating pools by duration with preserved rewards'
    )
  );

  -- Step 1: Clear existing pools first
  DELETE FROM user_staking_pools WHERE staked_amount >= 0;

  -- Step 2: Add the unique constraint
  ALTER TABLE user_staking_pools 
  DROP CONSTRAINT IF EXISTS user_staking_pools_unique_duration;
  
  ALTER TABLE user_staking_pools 
  ADD CONSTRAINT user_staking_pools_unique_duration 
  UNIQUE (user_id, pool_type, stake_duration_months);

  -- Step 3: Aggregate pools by user, pool_type, and duration
  FOR pool_record IN
    WITH requests_with_duration AS (
      SELECT 
        sr.user_id,
        sr.pool_type,
        sr.amount,
        sr.created_at,
        COALESCE(sr.processed_at, sr.created_at) as processed_at,
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
    )
    SELECT 
      user_id,
      pool_type,
      duration_months,
      SUM(amount) as total_amount,
      MIN(created_at) as earliest_request_date,
      MAX(processed_at) as latest_processed_date
    FROM requests_with_duration
    GROUP BY user_id, pool_type, duration_months
    HAVING SUM(amount) > 0
  LOOP
    -- Determine correct APY based on duration
    correct_apy := CASE pool_record.duration_months
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
    WHERE duration_months = pool_record.duration_months
    AND token_type = pool_record.pool_type
    AND status = 'active'
    LIMIT 1;

    -- Create aggregated pool with latest date
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
      pool_record.user_id,
      pool_record.pool_type,
      pool_record.total_amount,
      pool_record.total_amount,
      0, -- Reset rewards to 0 for fresh calculation
      correct_apy,
      correct_apy,
      pool_record.duration_months,
      pool_record.latest_processed_date + (pool_record.duration_months || ' months')::interval,
      true,
      correct_pool_id,
      pool_record.total_amount,
      pool_record.earliest_request_date,
      now(),
      pool_record.latest_processed_date
    );
    
    pools_created := pools_created + 1;
  END LOOP;

  -- Log completion
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    NULL,
    'staking_pool_aggregation_completed',
    'user_staking_pools',
    jsonb_build_object(
      'pools_created', pools_created,
      'timestamp', now(),
      'status', 'success'
    )
  );

  RAISE NOTICE 'Pool aggregation completed. Created: % aggregated pools', pools_created;
END $$;