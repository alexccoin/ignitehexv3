-- Add affiliate tracking fields to seed_str_applications
ALTER TABLE seed_str_applications
ADD COLUMN IF NOT EXISTS affiliate_name TEXT,
ADD COLUMN IF NOT EXISTS affiliate_email TEXT;