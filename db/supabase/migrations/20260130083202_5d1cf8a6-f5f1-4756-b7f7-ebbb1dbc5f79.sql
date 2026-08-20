
-- Clean up duplicate/empty STR staking pools
-- Only delete empty STR pools where user has another STR pool with actual staked amount

-- Step 1: Delete empty STR pools (staked_amount = 0, apy_rate = 0 or 11) 
-- for users who have at least one STR pool with staked_amount > 0
DELETE FROM user_staking_pools
WHERE id IN (
  SELECT empty_pool.id
  FROM user_staking_pools empty_pool
  WHERE empty_pool.pool_type = 'str'
  AND (empty_pool.staked_amount = 0 OR empty_pool.staked_amount IS NULL)
  AND (empty_pool.apy_rate = 0 OR empty_pool.apy_rate IS NULL OR empty_pool.apy_rate = 11.0)
  AND EXISTS (
    SELECT 1 
    FROM user_staking_pools funded_pool 
    WHERE funded_pool.user_id = empty_pool.user_id 
    AND funded_pool.pool_type = 'str'
    AND funded_pool.staked_amount > 0
    AND funded_pool.id != empty_pool.id
  )
);

-- Step 2: For users with multiple empty STR pools (no funded pool), keep only the newest one
DELETE FROM user_staking_pools
WHERE id IN (
  SELECT id FROM (
    SELECT 
      id,
      ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) as rn
    FROM user_staking_pools
    WHERE pool_type = 'str'
    AND (staked_amount = 0 OR staked_amount IS NULL)
    AND (apy_rate = 0 OR apy_rate IS NULL OR apy_rate = 11.0)
  ) ranked
  WHERE rn > 1
);
