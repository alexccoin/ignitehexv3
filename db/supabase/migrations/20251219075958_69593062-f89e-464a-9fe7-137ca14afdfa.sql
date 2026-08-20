-- Fix: Add str_stable balance to the correct user (str.alex = bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b)
-- Delete wrongly created records for wrong user
DELETE FROM user_staking_pools WHERE user_id = '12b744d5-3692-4f63-94df-dea27e02abb6' AND pool_type IN ('str_stable', 'str', 'wstr', 'ccos', 'arss', 'estr', 'domain') AND balance = 0 OR (user_id = '12b744d5-3692-4f63-94df-dea27e02abb6' AND pool_type = 'str_stable');

-- Insert str_stable for the correct user (str.alex)
INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned)
VALUES ('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'str_stable', 50000, 0, 0);