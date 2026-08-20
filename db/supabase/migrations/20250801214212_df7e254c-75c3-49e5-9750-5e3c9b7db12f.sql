-- Add transaction_hash column to staking_requests table if it doesn't exist
ALTER TABLE public.staking_requests 
ADD COLUMN IF NOT EXISTS transaction_hash TEXT;