-- Initialize staking pools for the user
SELECT initialize_user_staking_pools('bfb7c97b-7e1a-4de2-9d20-e71b3fd46555');

-- Check if the user has any staking pools after initialization
SELECT * FROM user_staking_pools WHERE user_id = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd46555';