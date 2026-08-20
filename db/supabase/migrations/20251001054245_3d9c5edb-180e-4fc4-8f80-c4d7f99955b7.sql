-- Fix balance rounding discrepancies in user_staking_pools
-- This ensures balance = staked_amount + rewards_earned for all pools

DO $$
DECLARE
  fixed_count INTEGER := 0;
  pool_record RECORD;
BEGIN
  -- Log the start of balance correction
  INSERT INTO security_audit_log (
    user_id, 
    action, 
    resource_type, 
    details
  ) VALUES (
    NULL,
    'balance_rounding_correction_started',
    'user_staking_pools',
    jsonb_build_object(
      'timestamp', now(),
      'description', 'Fixing balance rounding discrepancies where balance != staked_amount + rewards_earned'
    )
  );

  -- Fix all pools where balance doesn't match staked_amount + rewards_earned
  FOR pool_record IN
    SELECT 
      id,
      user_id,
      pool_type,
      balance as old_balance,
      staked_amount,
      rewards_earned,
      (staked_amount + rewards_earned) as correct_balance,
      ABS(balance - (staked_amount + rewards_earned)) as discrepancy
    FROM user_staking_pools
    WHERE ABS(balance - (staked_amount + rewards_earned)) > 0.000001
  LOOP
    -- Update the balance to the correct value
    UPDATE user_staking_pools
    SET 
      balance = pool_record.correct_balance,
      updated_at = now()
    WHERE id = pool_record.id;
    
    -- Log each correction
    INSERT INTO security_audit_log (
      user_id,
      action,
      resource_type,
      resource_id,
      details
    ) VALUES (
      pool_record.user_id,
      'balance_rounding_corrected',
      'user_staking_pools',
      pool_record.id::text,
      jsonb_build_object(
        'pool_type', pool_record.pool_type,
        'old_balance', pool_record.old_balance,
        'correct_balance', pool_record.correct_balance,
        'staked_amount', pool_record.staked_amount,
        'rewards_earned', pool_record.rewards_earned,
        'discrepancy', pool_record.discrepancy,
        'timestamp', now()
      )
    );
    
    fixed_count := fixed_count + 1;
  END LOOP;

  -- Log the completion with summary
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    NULL,
    'balance_rounding_correction_completed',
    'user_staking_pools',
    jsonb_build_object(
      'pools_corrected', fixed_count,
      'timestamp', now(),
      'status', 'success'
    )
  );

  RAISE NOTICE 'Balance rounding correction completed. Fixed % pools.', fixed_count;
END $$;