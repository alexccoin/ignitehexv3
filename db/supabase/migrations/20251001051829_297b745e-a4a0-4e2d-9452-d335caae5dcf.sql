-- Comprehensive fix for all users with APY mismatches
-- This will:
-- 1. Split pools if users have multiple durations
-- 2. Fix enhanced pools based on original selections
-- 3. Preserve all balances and rewards

-- First, split any pools that have multiple duration requests
SELECT split_user_pools_by_duration();

-- Then fix all enhanced pools to match original selections
SELECT fix_enhanced_pools_based_on_original_selections();

-- Verify the fixes
SELECT 
  'APY Fix Summary' as report,
  COUNT(DISTINCT user_id) as total_users_fixed,
  pool_type,
  stake_duration_months,
  AVG(dynamic_apy) as avg_apy,
  SUM(staked_amount) as total_staked,
  SUM(balance) as total_balance,
  SUM(rewards_earned) as total_rewards
FROM user_staking_pools
WHERE staked_amount > 0
AND is_enhanced_pool = true
GROUP BY pool_type, stake_duration_months
ORDER BY pool_type, stake_duration_months;