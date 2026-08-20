-- Add fields for existing STR.DOME domains
ALTER TABLE public.str_domains
ADD COLUMN IF NOT EXISTS is_from_str_dome BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS domains_count INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS is_main_domain BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS str_dome_purchase_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS str_dome_transaction_id TEXT;

-- Create index for main domain lookups
CREATE INDEX IF NOT EXISTS idx_str_domains_main ON public.str_domains(user_id, is_main_domain) WHERE is_main_domain = true;

-- Ensure only one main domain per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_main_domain_per_user ON public.str_domains(user_id) WHERE is_main_domain = true;