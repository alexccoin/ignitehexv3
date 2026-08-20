-- Add payment address fields to seed_str_affiliates
ALTER TABLE public.seed_str_affiliates
ADD COLUMN IF NOT EXISTS usdt_address TEXT,
ADD COLUMN IF NOT EXISTS usdt_network TEXT,
ADD COLUMN IF NOT EXISTS usdc_address TEXT,
ADD COLUMN IF NOT EXISTS usdc_network TEXT;