-- Add transaction_hash column for buyer payment proof
ALTER TABLE domain_marketplace_transactions
ADD COLUMN IF NOT EXISTS transaction_hash TEXT;

-- Add reserved status to listings
ALTER TABLE domain_marketplace_listings
DROP CONSTRAINT IF EXISTS domain_marketplace_listings_status_check;

ALTER TABLE domain_marketplace_listings
ADD CONSTRAINT domain_marketplace_listings_status_check 
CHECK (status IN ('active', 'pending_payment', 'reserved', 'sold', 'cancelled', 'suspended'));

-- Add is_admin_listing flag
ALTER TABLE domain_marketplace_listings
ADD COLUMN IF NOT EXISTS is_admin_listing BOOLEAN DEFAULT false;

-- Create index for admin listings
CREATE INDEX IF NOT EXISTS idx_listings_admin ON domain_marketplace_listings(is_admin_listing) WHERE is_admin_listing = true;