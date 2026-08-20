-- Move all supernode holders' str_stable balance to staked_amount (pending/locked)
-- This makes the balance show as "Locked" instead of "Available" in the wallet
UPDATE user_staking_pools usp
SET 
  staked_amount = usp.balance,
  balance = 0,
  updated_at = now()
FROM supernodes s
WHERE usp.user_id = s.user_id
AND usp.pool_type = 'str_stable'
AND usp.balance > 0;