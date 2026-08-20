-- Ensure domain_name is unique across the entire platform
-- First, check if there are any duplicates and remove them (keeping the oldest)
WITH duplicates AS (
  SELECT domain_name, MIN(created_at) as first_created
  FROM str_domains
  GROUP BY domain_name
  HAVING COUNT(*) > 1
)
DELETE FROM str_domains
WHERE id IN (
  SELECT sd.id
  FROM str_domains sd
  INNER JOIN duplicates d ON sd.domain_name = d.domain_name
  WHERE sd.created_at > d.first_created
);

-- Add unique constraint to domain_name if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'str_domains_domain_name_unique'
  ) THEN
    ALTER TABLE str_domains 
    ADD CONSTRAINT str_domains_domain_name_unique UNIQUE (domain_name);
  END IF;
END $$;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_str_domains_domain_name ON str_domains(domain_name);

-- Add check constraint to ensure domain_name format
ALTER TABLE str_domains 
DROP CONSTRAINT IF EXISTS str_domains_domain_name_format;

ALTER TABLE str_domains 
ADD CONSTRAINT str_domains_domain_name_format 
CHECK (
  domain_name IS NOT NULL 
  AND length(domain_name) >= 3 
  AND length(domain_name) <= 63
);

-- Ensure wallet addresses are unique too
ALTER TABLE domain_wallets
DROP CONSTRAINT IF EXISTS domain_wallets_wallet_address_key;

ALTER TABLE domain_wallets 
ADD CONSTRAINT domain_wallets_wallet_address_unique UNIQUE (wallet_address);

-- Create function to validate domain uniqueness before insert/update
CREATE OR REPLACE FUNCTION check_domain_uniqueness()
RETURNS TRIGGER AS $$
BEGIN
  -- Check if domain already exists (case-insensitive)
  IF EXISTS (
    SELECT 1 FROM str_domains 
    WHERE LOWER(domain_name) = LOWER(NEW.domain_name)
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) THEN
    RAISE EXCEPTION 'Domain name % already exists. Each str.domain must be unique.', NEW.domain_name;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for domain uniqueness
DROP TRIGGER IF EXISTS trigger_check_domain_uniqueness ON str_domains;

CREATE TRIGGER trigger_check_domain_uniqueness
  BEFORE INSERT OR UPDATE ON str_domains
  FOR EACH ROW
  EXECUTE FUNCTION check_domain_uniqueness();