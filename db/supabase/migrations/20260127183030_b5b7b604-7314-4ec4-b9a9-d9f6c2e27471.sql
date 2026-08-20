-- Add location and device tracking columns to private_seed_str_applications
ALTER TABLE public.private_seed_str_applications 
ADD COLUMN IF NOT EXISTS location_city text,
ADD COLUMN IF NOT EXISTS location_country text,
ADD COLUMN IF NOT EXISTS device_type text,
ADD COLUMN IF NOT EXISTS browser text;