-- Enable real-time updates for user_staking_pools table
ALTER TABLE user_staking_pools REPLICA IDENTITY FULL;

-- Add table to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE user_staking_pools;