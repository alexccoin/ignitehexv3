
-- Additional cleanup: Remove all STR pools with staked_amount = 0 where user has at least one STR pool with staked_amount > 0
-- This catches pools that were created with various APY rates but never funded

DELETE FROM user_staking_pools
WHERE id IN (
  SELECT empty_pool.id
  FROM user_staking_pools empty_pool
  WHERE empty_pool.pool_type = 'str'
  AND (empty_pool.staked_amount = 0 OR empty_pool.staked_amount IS NULL)
  AND empty_pool.rewards_earned = 0  -- Only delete if no rewards earned either
  AND EXISTS (
    SELECT 1 
    FROM user_staking_pools funded_pool 
    WHERE funded_pool.user_id = empty_pool.user_id 
    AND funded_pool.pool_type = 'str'
    AND funded_pool.staked_amount > 0
    AND funded_pool.id != empty_pool.id
  )
);
