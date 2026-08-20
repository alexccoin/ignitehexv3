
-- Add phone_number and admin_message columns, expand status options
ALTER TABLE public.ipo_listing_requests 
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS admin_message TEXT;

-- Drop old status constraint and add new one with more statuses
ALTER TABLE public.ipo_listing_requests DROP CONSTRAINT IF EXISTS ipo_listing_requests_status_check;
ALTER TABLE public.ipo_listing_requests ADD CONSTRAINT ipo_listing_requests_status_check 
  CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'suspended', 'more_info_requested'));
