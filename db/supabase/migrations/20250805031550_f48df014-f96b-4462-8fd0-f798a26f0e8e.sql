-- Enable real-time for user_staking_pools table
ALTER TABLE public.user_staking_pools REPLICA IDENTITY FULL;

-- Add table to realtime publication (this allows real-time subscriptions)
-- Note: This command will be handled by the Supabase dashboard automatically