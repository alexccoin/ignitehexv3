
-- Fix APY display issues for pools that aren't properly linked to enhanced pools
-- This ensures all pools show the correct APY based on their duration

DO $$
DECLARE
  pool_record RECORD;
  correct_enhanced_pool_id uuid;
  correct_apy numeric;
BEGIN
  -- Loop through all user staking pools that need fixing
  FOR pool_record IN
    SELECT 
      id,
      user_id,
      pool_type,
      stake_duration_months,
      apy_rate,
      dynamic_apy,
      enhanced_pool_id,
      is_enhanced_pool
    FROM user_staking_pools
    WHERE staked_amount > 0
    AND (enhanced_pool_id IS NULL OR is_enhanced_pool = false)
  LOOP
    -- Find the correct enhanced pool based on duration and token type
    SELECT esp.id, esp.apr_max
    INTO correct_enhanced_pool_id, correct_apy
    FROM enhanced_staking_pools esp
    WHERE esp.duration_months = pool_record.stake_duration_months
    AND esp.token_type = pool_record.pool_type
    AND esp.status = 'active'
    ORDER BY esp.created_at DESC
    LIMIT 1;

    -- If we found a matching enhanced pool, update the user's pool
    IF correct_enhanced_pool_id IS NOT NULL THEN
      UPDATE user_staking_pools
      SET 
        enhanced_pool_id = correct_enhanced_pool_id,
        is_enhanced_pool = true,
        apy_rate = correct_apy,
        dynamic_apy = correct_apy,
        updated_at = now()
      WHERE id = pool_record.id;

      RAISE NOTICE 'Fixed pool % for user % - Duration: % months, New APY: %', 
        pool_record.id, pool_record.user_id, pool_record.stake_duration_months, correct_apy;
    END IF;
  END LOOP;
END $$;

-- Verify the fixes
SELECT 
  'After Fix - User Pools' as check_type,
  COUNT(*) as total_pools,
  COUNT(*) FILTER (WHERE enhanced_pool_id IS NOT NULL) as pools_with_enhanced_link,
  COUNT(*) FILTER (WHERE is_enhanced_pool = true) as pools_marked_enhanced
FROM user_staking_pools
WHERE staked_amount > 0;
