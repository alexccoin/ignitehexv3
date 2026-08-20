-- Add domain-specific fields to staking_requests table
ALTER TABLE public.staking_requests 
ADD COLUMN IF NOT EXISTS str_domain_username TEXT,
ADD COLUMN IF NOT EXISTS full_name TEXT,
ADD COLUMN IF NOT EXISTS str_domain_owned TEXT;