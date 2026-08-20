-- Add phone column to private_seed_str_applications
ALTER TABLE public.private_seed_str_applications 
ADD COLUMN IF NOT EXISTS phone text;