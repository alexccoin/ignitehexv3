-- Reset STR staking pool for the user
UPDATE user_staking_pools 
SET 
  balance = 0,
  staked_amount = 0,
  rewards_earned = 0,
  updated_at = now()
WHERE user_id = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd46555' AND pool_type = 'str';

-- Clear all staking requests for this user
DELETE FROM staking_requests WHERE user_id = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd46555';

-- Clear any arss transactions (mission activity log)
DELETE FROM arss_transactions WHERE user_id = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd46555';