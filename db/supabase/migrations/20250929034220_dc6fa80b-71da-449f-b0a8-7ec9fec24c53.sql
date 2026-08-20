-- Create enhanced pool migration based on actual user staking requests
-- This replaces the previous migration with one that honors user's requested lock periods

CREATE OR REPLACE FUNCTION public.migrate_users_to_enhanced_pools_by_request()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  staking_record RECORD;
  pool_duration INTEGER;
  enhanced_pool enhanced_staking_pools%ROWTYPE;
  total_migrations INTEGER := 0;
  migrations_applied jsonb := '[]'::jsonb;
  migration_record jsonb;
BEGIN
  -- Log the start of migration
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'enhanced_pool_migration_by_request_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  -- Loop through users with basic pools that need migration
  FOR user_record IN
    SELECT DISTINCT user_id, pool_type, balance, staked_amount, rewards_earned
    FROM user_staking_pools 
    WHERE is_enhanced_pool = false 
    AND staked_amount > 0
  LOOP
    -- Find the user's latest approved staking request to determine their preferred lock period
    SELECT * INTO staking_record
    FROM staking_requests 
    WHERE user_id = user_record.user_id 
    AND pool_type = user_record.pool_type
    AND status = 'approved'
    AND request_type = 'stake'
    ORDER BY processed_at DESC 
    LIMIT 1;
    
    -- Extract lock period from description or default based on amount
    pool_duration := 3; -- Default fallback
    
    IF staking_record.description IS NOT NULL THEN
      -- Extract duration from "Lock Period: X months" pattern
      IF staking_record.description ~ 'Lock Period: (\d+) months' THEN
        pool_duration := (regexp_match(staking_record.description, 'Lock Period: (\d+) months'))[1]::INTEGER;
      -- Handle other duration patterns
      ELSIF staking_record.description ~ '(\d+) months?' THEN
        pool_duration := (regexp_match(staking_record.description, '(\d+) months?'))[1]::INTEGER;
      -- Handle specific amounts to determine duration (based on typical patterns)
      ELSIF user_record.staked_amount >= 200000 THEN
        pool_duration := 24; -- Large stakes typically get longer periods
      ELSIF user_record.staked_amount >= 100000 THEN
        pool_duration := 12;
      ELSIF user_record.staked_amount >= 50000 THEN
        pool_duration := 6;
      END IF;
    END IF;
    
    -- Ensure duration is within reasonable bounds
    pool_duration := GREATEST(3, LEAST(48, pool_duration));
    
    -- Find or get the appropriate enhanced pool for this duration and token type
    SELECT * INTO enhanced_pool
    FROM enhanced_staking_pools
    WHERE duration_months = pool_duration
    AND token_type = user_record.pool_type
    AND status = 'active'
    LIMIT 1;
    
    -- If no pool exists for this duration, use the closest one
    IF NOT FOUND THEN
      SELECT * INTO enhanced_pool
      FROM enhanced_staking_pools
      WHERE token_type = user_record.pool_type
      AND status = 'active'
      ORDER BY ABS(duration_months - pool_duration)
      LIMIT 1;
    END IF;
    
    -- If still no pool found, skip this user
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    
    -- Update the user's pool to enhanced
    UPDATE user_staking_pools
    SET 
      is_enhanced_pool = true,
      enhanced_pool_id = enhanced_pool.id,
      stake_duration_months = enhanced_pool.duration_months,
      lock_end_date = now() + (enhanced_pool.duration_months || ' months')::interval,
      network_efficiency = 1.0,
      dynamic_apy = enhanced_pool.apr_max,
      original_stake_amount = user_record.staked_amount,
      updated_at = now()
    WHERE user_id = user_record.user_id 
    AND pool_type = user_record.pool_type;
    
    -- Track this migration
    migration_record := jsonb_build_object(
      'user_id', user_record.user_id,
      'pool_type', user_record.pool_type,
      'migrated_stake', user_record.staked_amount,
      'migrated_balance', user_record.balance,
      'rewards_preserved', user_record.rewards_earned,
      'duration_months', enhanced_pool.duration_months,
      'enhanced_pool_id', enhanced_pool.id,
      'lock_end_date', now() + (enhanced_pool.duration_months || ' months')::interval,
      'request_based', staking_record.id IS NOT NULL
    );
    
    migrations_applied := migrations_applied || migration_record;
    total_migrations := total_migrations + 1;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'enhanced_pool_migration_by_request_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'total_migrations', total_migrations,
      'migrations_applied', migrations_applied,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_migrations', total_migrations,
    'migrations_applied', migrations_applied,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'enhanced_pool_migration_by_request_failed', 
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
$function$;