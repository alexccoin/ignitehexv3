-- Add last_reward_date to track daily distributions
ALTER TABLE user_staking_pools 
ADD COLUMN last_reward_date DATE;

-- Create index for better performance
CREATE INDEX idx_user_staking_pools_last_reward_date ON user_staking_pools(last_reward_date);