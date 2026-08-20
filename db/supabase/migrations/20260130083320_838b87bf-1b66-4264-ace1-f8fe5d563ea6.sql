
-- Final cleanup: Remove empty STR pools (staked = 0, no rewards) from users who have funded pools
-- This is more aggressive but safe since it only affects pools with zero value

DELETE FROM user_staking_pools
WHERE pool_type = 'str'
AND (staked_amount = 0 OR staked_amount IS NULL)
AND (rewards_earned = 0 OR rewards_earned IS NULL)
AND user_id IN (
  SELECT DISTINCT user_id 
  FROM user_staking_pools 
  WHERE pool_type = 'str' 
  AND staked_amount > 0
);
