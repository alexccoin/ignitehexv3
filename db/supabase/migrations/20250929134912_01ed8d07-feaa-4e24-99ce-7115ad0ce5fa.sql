-- Create comprehensive function to safely migrate and correct all user data from acceptance to today
CREATE OR REPLACE FUNCTION comprehensive_user_migration_from_acceptance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  user_record RECORD;
  corrections_applied INTEGER := 0;
  total_users_processed INTEGER := 0;
  migration_summary jsonb := '[]'::jsonb;
  migration_record jsonb;
  expected_balance NUMERIC;
  total_rewards_should_be NUMERIC;
  correct_pool enhanced_staking_pools%ROWTYPE;
  original_duration INTEGER;
  acceptance_date TIMESTAMP WITH TIME ZONE;
  days_since_acceptance INTEGER;
  calculated_rewards NUMERIC;
BEGIN
  -- Log the start of comprehensive migration
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'comprehensive_user_migration_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  -- Loop through all approved users with staking activities
  FOR user_record IN
    SELECT DISTINCT
      up.user_id,
      up.full_name,
      up.status,
      up.created_at as profile_created,
      COALESCE(au.email_confirmed_at, au.created_at) as acceptance_date,
      usp.pool_type,
      usp.staked_amount,
      usp.balance,
      usp.rewards_earned,
      usp.apy_rate,
      usp.dynamic_apy,
      usp.is_enhanced_pool,
      usp.enhanced_pool_id,
      usp.stake_duration_months,
      -- Get original duration from latest staking request
      (SELECT 
        COALESCE(
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
            ELSE 3
          END,
          CASE 
            WHEN usp.staked_amount >= 500000 THEN 48
            WHEN usp.staked_amount >= 200000 THEN 24
            WHEN usp.staked_amount >= 100000 THEN 12
            WHEN usp.staked_amount >= 50000 THEN 6
            ELSE 3
          END
        )
       FROM staking_requests sr 
       WHERE sr.user_id = up.user_id 
       AND sr.pool_type = usp.pool_type
       AND sr.status = 'approved'
       AND sr.request_type = 'stake'
       ORDER BY sr.processed_at DESC 
       LIMIT 1) as original_duration_months
    FROM user_profiles up
    JOIN auth.users au ON up.user_id = au.id
    LEFT JOIN user_staking_pools usp ON up.user_id = usp.user_id
    WHERE up.status = 'approved'
    AND usp.staked_amount > 0
    ORDER BY COALESCE(au.email_confirmed_at, au.created_at) ASC
  LOOP
    total_users_processed := total_users_processed + 1;
    acceptance_date := user_record.acceptance_date;
    days_since_acceptance := EXTRACT(DAYS FROM now() - acceptance_date);
    original_duration := COALESCE(user_record.original_duration_months, 3);
    
    -- Find the correct enhanced pool for this duration and token type
    SELECT * INTO correct_pool
    FROM enhanced_staking_pools
    WHERE duration_months = original_duration
    AND token_type = user_record.pool_type
    AND status = 'active'
    LIMIT 1;
    
    -- If no exact match, find the closest duration pool
    IF NOT FOUND THEN
      SELECT * INTO correct_pool
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
    
    -- Calculate what rewards should be based on time since acceptance and APY
    -- Use a simple calculation: (staked_amount * APY * days_since_acceptance) / (365 * 100)
    calculated_rewards := (user_record.staked_amount * correct_pool.apr_max * days_since_acceptance) / (365.0 * 100.0);
    expected_balance := user_record.staked_amount + calculated_rewards;
    
    -- Check if correction is needed
    IF user_record.enhanced_pool_id != correct_pool.id OR 
       ABS(user_record.dynamic_apy - correct_pool.apr_max) > 0.5 OR
       ABS(user_record.apy_rate - correct_pool.apr_max) > 0.5 OR
       user_record.balance < user_record.staked_amount OR
       ABS(user_record.rewards_earned - calculated_rewards) > (calculated_rewards * 0.1) THEN -- 10% tolerance
      
      -- Update the user's pool with correct values
      UPDATE user_staking_pools
      SET 
        enhanced_pool_id = correct_pool.id,
        stake_duration_months = correct_pool.duration_months,
        dynamic_apy = correct_pool.apr_max,
        apy_rate = correct_pool.apr_max,
        balance = expected_balance,
        rewards_earned = calculated_rewards,
        is_enhanced_pool = true,
        lock_end_date = acceptance_date + (correct_pool.duration_months || ' months')::interval,
        updated_at = now()
      WHERE user_id = user_record.user_id 
      AND pool_type = user_record.pool_type;
      
      -- Create corrective transaction for the reward adjustment
      IF ABS(user_record.rewards_earned - calculated_rewards) > 1 THEN
        INSERT INTO arss_transactions (
          user_id,
          amount,
          transaction_type,
          source_type,
          description,
          status
        ) VALUES (
          user_record.user_id,
          calculated_rewards - user_record.rewards_earned,
          'migration_correction',
          'comprehensive_migration',
          'Comprehensive migration reward correction: ' || user_record.full_name || ' (' || 
          CASE WHEN (calculated_rewards - user_record.rewards_earned) > 0 THEN '+' ELSE '' END || 
          (calculated_rewards - user_record.rewards_earned)::text || ' ' || user_record.pool_type || ')',
          'completed'
        );
      END IF;
      
      -- Track this migration
      migration_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'full_name', user_record.full_name,
        'pool_type', user_record.pool_type,
        'acceptance_date', acceptance_date,
        'days_since_acceptance', days_since_acceptance,
        'original_duration_selected', original_duration,
        'staked_amount', user_record.staked_amount,
        'previous_balance', user_record.balance,
        'corrected_balance', expected_balance,
        'previous_rewards', user_record.rewards_earned,
        'corrected_rewards', calculated_rewards,
        'previous_apy', user_record.dynamic_apy,
        'corrected_apy', correct_pool.apr_max,
        'enhanced_pool_name', correct_pool.name,
        'correction_type', 
          CASE 
            WHEN user_record.balance < user_record.staked_amount THEN 'balance_fix'
            WHEN ABS(user_record.dynamic_apy - correct_pool.apr_max) > 0.5 THEN 'apy_fix'
            WHEN ABS(user_record.rewards_earned - calculated_rewards) > (calculated_rewards * 0.1) THEN 'rewards_recalc'
            ELSE 'enhancement_upgrade'
          END
      );
      
      migration_summary := migration_summary || migration_record;
      corrections_applied := corrections_applied + 1;
    END IF;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'comprehensive_user_migration_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'total_users_processed', total_users_processed,
      'corrections_applied', corrections_applied,
      'migration_summary', migration_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_users_processed', total_users_processed,
    'corrections_applied', corrections_applied,
    'migration_summary', migration_summary,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'comprehensive_user_migration_failed', 
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