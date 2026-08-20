-- Safe migration function to move users from basic to enhanced pools
CREATE OR REPLACE FUNCTION migrate_users_to_enhanced_pools()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  user_record RECORD;
  enhanced_pool_id uuid;
  migration_count integer := 0;
  migrations_summary jsonb := '[]'::jsonb;
  migration_record jsonb;
BEGIN
  -- Log the start of migration
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'enhanced_pool_migration_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now(), 'initiated_by', auth.uid())
  );

  -- Loop through users with basic staking pools that aren't enhanced yet
  FOR user_record IN
    SELECT 
      user_id,
      pool_type,
      balance,
      staked_amount,
      rewards_earned,
      apy_rate,
      created_at,
      id as old_pool_id
    FROM user_staking_pools
    WHERE is_enhanced_pool = false
    AND staked_amount > 0
  LOOP
    -- Find appropriate enhanced pool (default to 3-month for existing stakes)
    SELECT id INTO enhanced_pool_id
    FROM enhanced_staking_pools
    WHERE token_type = user_record.pool_type
    AND duration_months = 3  -- Default migration to 3-month pools
    AND status = 'active'
    LIMIT 1;

    IF enhanced_pool_id IS NOT NULL THEN
      -- Create new enhanced pool entry
      INSERT INTO user_staking_pools (
        user_id,
        pool_type,
        balance,
        staked_amount,
        rewards_earned,
        apy_rate,
        enhanced_pool_id,
        is_enhanced_pool,
        stake_duration_months,
        lock_end_date,
        original_stake_amount,
        dynamic_apy,
        network_efficiency,
        created_at
      ) VALUES (
        user_record.user_id,
        user_record.pool_type,
        user_record.balance,
        user_record.staked_amount,
        user_record.rewards_earned,
        user_record.apy_rate,
        enhanced_pool_id,
        true,
        3, -- Default to 3 months for existing stakes
        now() + interval '3 months', -- Set lock end date
        user_record.staked_amount,
        user_record.apy_rate,
        1.0,
        user_record.created_at
      );

      -- Mark old pool as migrated (don't delete to preserve history)
      UPDATE user_staking_pools 
      SET 
        staked_amount = 0,
        balance = 0,
        updated_at = now()
      WHERE id = user_record.old_pool_id;

      -- Record this migration
      migration_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'pool_type', user_record.pool_type,
        'migrated_balance', user_record.balance,
        'migrated_stake', user_record.staked_amount,
        'migrated_rewards', user_record.rewards_earned,
        'enhanced_pool_id', enhanced_pool_id,
        'old_pool_id', user_record.old_pool_id
      );
      
      migrations_summary := migrations_summary || migration_record;
      migration_count := migration_count + 1;
    END IF;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'enhanced_pool_migration_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'total_migrations', migration_count,
      'migrations_summary', migrations_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_migrations', migration_count,
    'migrations_applied', migrations_summary,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'timestamp', now()
  );
END;
$$;

-- Function to safely rollback migration if needed
CREATE OR REPLACE FUNCTION rollback_enhanced_pool_migration()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  rollback_count integer := 0;
BEGIN
  -- This function can be used to rollback if something goes wrong
  -- It restores the original basic pools from the enhanced ones
  
  WITH enhanced_pools_to_rollback AS (
    SELECT 
      user_id,
      pool_type,
      balance,
      staked_amount,
      rewards_earned,
      apy_rate,
      created_at
    FROM user_staking_pools
    WHERE is_enhanced_pool = true
    AND enhanced_pool_id IS NOT NULL
  )
  INSERT INTO user_staking_pools (
    user_id,
    pool_type,
    balance,
    staked_amount,
    rewards_earned,
    apy_rate,
    is_enhanced_pool,
    created_at
  )
  SELECT 
    user_id,
    pool_type,
    balance,
    staked_amount,
    rewards_earned,
    apy_rate,
    false,
    created_at
  FROM enhanced_pools_to_rollback;
  
  GET DIAGNOSTICS rollback_count = ROW_COUNT;
  
  -- Delete the enhanced pools after rollback
  DELETE FROM user_staking_pools WHERE is_enhanced_pool = true;

  RETURN jsonb_build_object(
    'success', true,
    'rollback_count', rollback_count,
    'timestamp', now()
  );
END;
$$;