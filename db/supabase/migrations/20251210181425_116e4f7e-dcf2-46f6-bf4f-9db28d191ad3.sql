-- Add reservation expiry tracking to listings
ALTER TABLE domain_marketplace_listings 
ADD COLUMN IF NOT EXISTS reserved_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS reserved_by UUID,
ADD COLUMN IF NOT EXISTS reservation_expires_at TIMESTAMP WITH TIME ZONE;

-- Add reservation expiry tracking to transactions
ALTER TABLE domain_marketplace_transactions 
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;

-- Create function to release expired reservations
CREATE OR REPLACE FUNCTION release_expired_domain_reservations()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  released_count INTEGER;
BEGIN
  -- Update listings that have expired reservations back to active
  UPDATE domain_marketplace_listings
  SET 
    status = 'active',
    reserved_at = NULL,
    reserved_by = NULL,
    reservation_expires_at = NULL
  WHERE 
    status = 'reserved' 
    AND reservation_expires_at IS NOT NULL 
    AND reservation_expires_at < NOW();
  
  GET DIAGNOSTICS released_count = ROW_COUNT;
  
  -- Cancel corresponding transactions
  UPDATE domain_marketplace_transactions
  SET status = 'cancelled'
  WHERE 
    status = 'pending'
    AND expires_at IS NOT NULL
    AND expires_at < NOW();
  
  RETURN released_count;
END;
$$;