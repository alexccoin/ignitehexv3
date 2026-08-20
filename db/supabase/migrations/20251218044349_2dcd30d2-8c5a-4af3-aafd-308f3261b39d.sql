
-- Delete all zero-balance empty staking pools (cleanup erroneous records)
DELETE FROM user_staking_pools 
WHERE staked_amount = 0 
  AND balance = 0 
  AND (rewards_earned = 0 OR rewards_earned IS NULL);
