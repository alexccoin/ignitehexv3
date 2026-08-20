-- Clean up duplicate domain listings, keeping only the most recent one
WITH duplicates AS (
  SELECT id, domain_name, created_at,
    ROW_NUMBER() OVER (PARTITION BY domain_name ORDER BY created_at DESC) as rn
  FROM domain_marketplace_listings
  WHERE status IN ('active', 'reserved', 'pending')
)
UPDATE domain_marketplace_listings 
SET status = 'cancelled'
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- Now create the unique index for active listings
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_domain_listing 
ON public.domain_marketplace_listings (domain_name) 
WHERE status IN ('active', 'reserved', 'pending');

-- Add unique constraint on str_domains
ALTER TABLE public.str_domains
DROP CONSTRAINT IF EXISTS str_domains_domain_name_key;

ALTER TABLE public.str_domains
DROP CONSTRAINT IF EXISTS str_domains_domain_name_unique;

-- Clean up duplicate str_domains first
WITH str_dups AS (
  SELECT id, domain_name, created_at,
    ROW_NUMBER() OVER (PARTITION BY domain_name ORDER BY created_at DESC) as rn
  FROM str_domains
)
DELETE FROM str_domains
WHERE id IN (
  SELECT id FROM str_dups WHERE rn > 1
);

-- Now add the unique constraint
ALTER TABLE public.str_domains
ADD CONSTRAINT str_domains_domain_name_unique UNIQUE (domain_name);

-- Create a function to check if a domain is already listed or reserved
CREATE OR REPLACE FUNCTION public.is_domain_available_for_listing(p_domain_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM domain_marketplace_listings 
    WHERE domain_name = p_domain_name 
    AND status IN ('active', 'reserved', 'pending')
  );
$$;