
-- Fix supernode STR stable distribution: should only be in pending (staked_amount), not available (balance)
-- For user bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b who has 50K in both balance and staked_amount

UPDATE user_staking_pools 
SET balance = 0 
WHERE pool_type = 'str_stable' 
AND balance > 0;

-- Also ensure all str_stable pools only show in pending for supernode users
-- The 50K should ONLY be in staked_amount, not in balance
