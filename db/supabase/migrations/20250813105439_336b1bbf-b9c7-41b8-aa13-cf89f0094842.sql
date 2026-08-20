UPDATE user_staking_pools 
SET apy_rate = 22.0, updated_at = now()
WHERE user_id = 'c49a3109-8624-4f60-a280-ba0de1a6245d' 
AND pool_type = 'str';