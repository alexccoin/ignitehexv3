-- Drop the unique constraint that's blocking multiple staking entries at the same duration
-- This allows users to have multiple staking pools for the same token type and duration (added on different dates)
ALTER TABLE user_staking_pools DROP CONSTRAINT IF EXISTS user_staking_pools_unique_duration;
ALTER TABLE user_staking_pools DROP CONSTRAINT IF EXISTS user_staking_pools_user_id_pool_type_stake_duration_months_key;