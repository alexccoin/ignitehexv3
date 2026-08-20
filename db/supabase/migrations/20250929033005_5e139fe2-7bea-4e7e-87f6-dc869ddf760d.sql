-- Fix the migration function to handle existing enhanced pools safely
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
  existing_enhanced_pool_id uuid;
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
    -- Check if user already has an enhanced pool for this token type
    SELECT id INTO existing_enhanced_pool_id
    FROM user_staking_pools
    WHERE user_id = user_record.user_id
    AND pool_type = user_record.pool_type
    AND is_enhanced_pool = true
    LIMIT 1;

    -- Only migrate if no enhanced pool exists for this user/token combination
    IF existing_enhanced_pool_id IS NULL THEN
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

        -- Mark old pool as migrated (set balances to 0 to avoid double counting)
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
    ELSE
      -- User already has enhanced pool, just migrate the values
      UPDATE user_staking_pools 
      SET 
        balance = balance + user_record.balance,
        staked_amount = staked_amount + user_record.staked_amount,
        rewards_earned = rewards_earned + user_record.rewards_earned,
        updated_at = now()
      WHERE id = existing_enhanced_pool_id;

      -- Zero out the old pool
      UPDATE user_staking_pools 
      SET 
        staked_amount = 0,
        balance = 0,
        updated_at = now()
      WHERE id = user_record.old_pool_id;

      -- Record this consolidation
      migration_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'pool_type', user_record.pool_type,
        'consolidated_balance', user_record.balance,
        'consolidated_stake', user_record.staked_amount,
        'consolidated_rewards', user_record.rewards_earned,
        'existing_enhanced_pool_id', existing_enhanced_pool_id,
        'old_pool_id', user_record.old_pool_id,
        'action', 'consolidated_to_existing'
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