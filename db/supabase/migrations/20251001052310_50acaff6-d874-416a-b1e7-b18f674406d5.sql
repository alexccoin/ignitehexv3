-- Comprehensive APY fix for all users with mismatched APYs
-- This will update ALL pools to match the correct enhanced pool APY rates

-- First, let's see the current state of pools with wrong APYs
SELECT 
  'Before Fix - Pools with Mismatched APY' as status,
  up.email_address,
  usp.pool_type,
  usp.stake_duration_months,
  usp.apy_rate as current_apy,
  usp.dynamic_apy as current_dynamic_apy,
  esp.apr_max as should_be_apy,
  usp.staked_amount,
  usp.balance,
  usp.rewards_earned,
  CASE 
    WHEN usp.enhanced_pool_id IS NULL THEN 'Not Linked'
    WHEN usp.apy_rate != esp.apr_max THEN 'Wrong APY'
    WHEN usp.dynamic_apy != esp.apr_max THEN 'Wrong Dynamic APY'
    ELSE 'OK'
  END as issue
FROM user_staking_pools usp
JOIN user_profiles up ON usp.user_id = up.user_id
LEFT JOIN enhanced_staking_pools esp ON usp.enhanced_pool_id = esp.id
WHERE usp.staked_amount > 0
AND (
  usp.enhanced_pool_id IS NULL 
  OR usp.apy_rate != esp.apr_max 
  OR usp.dynamic_apy != esp.apr_max
  OR usp.is_enhanced_pool = false
)
ORDER BY up.email_address, usp.pool_type, usp.stake_duration_months
LIMIT 50;

-- Now fix ALL pools by matching them to correct enhanced_staking_pools
UPDATE user_staking_pools usp
SET 
  enhanced_pool_id = esp.id,
  is_enhanced_pool = true,
  apy_rate = esp.apr_max,
  dynamic_apy = esp.apr_max,
  updated_at = now()
FROM enhanced_staking_pools esp
WHERE usp.stake_duration_months = esp.duration_months
AND usp.pool_type = esp.token_type
AND esp.status = 'active'
AND usp.staked_amount > 0
AND (
  usp.enhanced_pool_id IS NULL 
  OR usp.enhanced_pool_id != esp.id
  OR usp.apy_rate != esp.apr_max 
  OR usp.dynamic_apy != esp.apr_max
  OR usp.is_enhanced_pool = false
);

-- Verify the fixes
SELECT 
  'After Fix - Summary' as status,
  pool_type,
  stake_duration_months,
  COUNT(*) as pools_fixed,
  AVG(apy_rate) as avg_apy,
  AVG(dynamic_apy) as avg_dynamic_apy,
  SUM(staked_amount) as total_staked,
  SUM(balance) as total_balance,
  SUM(rewards_earned) as total_rewards
FROM user_staking_pools
WHERE staked_amount > 0
AND is_enhanced_pool = true
GROUP BY pool_type, stake_duration_months
ORDER BY pool_type, stake_duration_months;