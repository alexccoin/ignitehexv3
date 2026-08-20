-- Add missing columns to private_seed_str_applications
ALTER TABLE public.private_seed_str_applications 
ADD COLUMN IF NOT EXISTS street_address text,
ADD COLUMN IF NOT EXISTS city text,
ADD COLUMN IF NOT EXISTS state_province text,
ADD COLUMN IF NOT EXISTS postal_code text,
ADD COLUMN IF NOT EXISTS country text,
ADD COLUMN IF NOT EXISTS presented_by text,
ADD COLUMN IF NOT EXISTS purpose_of_report text,
ADD COLUMN IF NOT EXISTS signature_first_name text,
ADD COLUMN IF NOT EXISTS signature_last_name text,
ADD COLUMN IF NOT EXISTS signature_date timestamp with time zone;