-- Add currency column to domain_marketplace_listings
ALTER TABLE public.domain_marketplace_listings 
ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'USD';

-- Add currency column to domain_marketplace_bids
ALTER TABLE public.domain_marketplace_bids 
ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'USD';

-- Add currency column to domain_marketplace_transactions
ALTER TABLE public.domain_marketplace_transactions 
ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'USD';