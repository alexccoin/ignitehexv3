-- Add missing column to private_seed_str_applications
ALTER TABLE public.private_seed_str_applications 
ADD COLUMN IF NOT EXISTS acknowledgment_accepted boolean NOT NULL DEFAULT false;