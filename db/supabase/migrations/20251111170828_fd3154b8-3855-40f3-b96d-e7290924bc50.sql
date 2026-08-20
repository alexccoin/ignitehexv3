
-- Fix STARW purchases constraints to allow manual entries
-- Make arss_bonus and stage nullable since they may not be known for manual entries

ALTER TABLE public.starw_purchases 
ALTER COLUMN arss_bonus DROP NOT NULL;

ALTER TABLE public.starw_purchases 
ALTER COLUMN stage DROP NOT NULL;

-- Add default values where appropriate
ALTER TABLE public.starw_purchases 
ALTER COLUMN arss_bonus SET DEFAULT 'N/A';

ALTER TABLE public.starw_purchases 
ALTER COLUMN stage SET DEFAULT 0;

-- Add comment for clarity
COMMENT ON COLUMN public.starw_purchases.arss_bonus IS 'ARSS bonus info, can be N/A for manual entries';
COMMENT ON COLUMN public.starw_purchases.stage IS 'Purchase stage number, 0 for manual/unknown entries';
