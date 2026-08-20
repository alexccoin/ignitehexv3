-- First, let's create a composite unique constraint to allow multiple pools per user/token type
-- but ensure uniqueness for each duration combination

-- Drop the existing unique constraint on user_id, pool_type if it exists
ALTER TABLE user_staking_pools DROP CONSTRAINT IF EXISTS user_staking_pools_user_id_pool_type_key;

-- Add a new unique constraint that includes the stake_duration_months
ALTER TABLE user_staking_pools ADD CONSTRAINT user_staking_pools_unique_duration 
UNIQUE (user_id, pool_type, stake_duration_months);

-- Add an index for better performance when querying by duration
CREATE INDEX IF NOT EXISTS idx_user_staking_pools_duration 
ON user_staking_pools (user_id, pool_type, stake_duration_months);

-- Create a function to split existing pools based on historical staking requests
CREATE OR REPLACE FUNCTION split_user_pools_by_duration()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  pool_record RECORD;
  request_record RECORD;
  total_split INTEGER := 0;
  split_summary jsonb := '[]'::jsonb;
  split_record jsonb;
  remaining_amount NUMERIC;
  total_requests_amount NUMERIC;
  pool_split_amount NUMERIC;
BEGIN
  -- Log the start of pool splitting
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'pool_splitting_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  -- Process each user's pools that have multiple requests with different durations
  FOR pool_record IN
    SELECT DISTINCT
      usp.user_id,
      usp.pool_type,
      usp.staked_amount,
      usp.balance,
      usp.rewards_earned,
      usp.id as original_pool_id
    FROM user_staking_pools usp
    WHERE usp.staked_amount > 0
    AND EXISTS (
      -- Only process pools where user has multiple requests with different durations
      SELECT 1 
      FROM staking_requests sr1, staking_requests sr2
      WHERE sr1.user_id = usp.user_id 
      AND sr1.pool_type = usp.pool_type
      AND sr1.status = 'approved'
      AND sr1.request_type = 'stake'
      AND sr2.user_id = usp.user_id 
      AND sr2.pool_type = usp.pool_type
      AND sr2.status = 'approved'
      AND sr2.request_type = 'stake'
      AND sr1.id != sr2.id
      AND EXTRACT(months FROM JUSTIFY_INTERVAL(
        CASE 
          WHEN sr1.description ~ 'Lock Period: (\d+) months' THEN 
            (regexp_match(sr1.description, 'Lock Period: (\d+) months'))[1]::INTEGER || ' months'
          ELSE '3 months'
        END::interval
      )) != EXTRACT(months FROM JUSTIFY_INTERVAL(
        CASE 
          WHEN sr2.description ~ 'Lock Period: (\d+) months' THEN 
            (regexp_match(sr2.description, 'Lock Period: (\d+) months'))[1]::INTEGER || ' months'
          ELSE '3 months'
        END::interval
      ))
    )
  LOOP
    -- Get total amount from all staking requests for this user/pool type
    SELECT COALESCE(SUM(amount), 0) INTO total_requests_amount
    FROM staking_requests 
    WHERE user_id = pool_record.user_id 
    AND pool_type = pool_record.pool_type
    AND status = 'approved'
    AND request_type = 'stake';
    
    remaining_amount := pool_record.staked_amount;
    
    -- Create separate pools for each unique duration for this user/pool type
    FOR request_record IN
      SELECT DISTINCT
        CASE 
          WHEN description ~ 'Lock Period: (\d+) months' THEN 
            (regexp_match(description, 'Lock Period: (\d+) months'))[1]::INTEGER
          ELSE 3
        END as duration_months,
        SUM(amount) as total_amount_for_duration
      FROM staking_requests 
      WHERE user_id = pool_record.user_id 
      AND pool_type = pool_record.pool_type
      AND status = 'approved'
      AND request_type = 'stake'
      GROUP BY 1
      ORDER BY 1
    LOOP
      -- Calculate proportional amount for this duration
      IF total_requests_amount > 0 THEN
        pool_split_amount := (request_record.total_amount_for_duration / total_requests_amount) * pool_record.staked_amount;
      ELSE
        pool_split_amount := remaining_amount;
      END IF;
      
      -- Don't create pools with zero or negative amounts
      IF pool_split_amount <= 0 THEN
        CONTINUE;
      END IF;
      
      -- Check if pool already exists for this duration
      IF NOT EXISTS (
        SELECT 1 FROM user_staking_pools 
        WHERE user_id = pool_record.user_id 
        AND pool_type = pool_record.pool_type 
        AND stake_duration_months = request_record.duration_months
      ) THEN
        -- Insert new pool for this duration
        INSERT INTO user_staking_pools (
          user_id,
          pool_type,
          balance,
          staked_amount,
          rewards_earned,
          apy_rate,
          stake_duration_months,
          lock_end_date,
          is_enhanced_pool,
          created_at,
          updated_at
        ) VALUES (
          pool_record.user_id,
          pool_record.pool_type,
          pool_split_amount,
          pool_split_amount,
          (pool_record.rewards_earned / pool_record.staked_amount) * pool_split_amount, -- Proportional rewards
          CASE request_record.duration_months
            WHEN 3 THEN 11.0
            WHEN 6 THEN 13.0
            WHEN 12 THEN 15.0
            WHEN 24 THEN 18.0
            WHEN 36 THEN 22.0
            WHEN 48 THEN 25.0
            ELSE 11.0
          END,
          request_record.duration_months,
          now() + (request_record.duration_months || ' months')::interval,
          true,
          now(),
          now()
        );
        
        -- Track this split
        split_record := jsonb_build_object(
          'user_id', pool_record.user_id,
          'pool_type', pool_record.pool_type,
          'duration_months', request_record.duration_months,
          'split_amount', pool_split_amount,
          'original_pool_id', pool_record.original_pool_id
        );
        
        split_summary := split_summary || split_record;
        total_split := total_split + 1;
        remaining_amount := remaining_amount - pool_split_amount;
      END IF;
    END LOOP;
    
    -- Delete the original pool if we successfully split it
    IF total_split > 0 THEN
      DELETE FROM user_staking_pools WHERE id = pool_record.original_pool_id;
    END IF;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'pool_splitting_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'total_split', total_split,
      'split_summary', split_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_split', total_split,
    'split_summary', split_summary,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'pool_splitting_failed', 
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