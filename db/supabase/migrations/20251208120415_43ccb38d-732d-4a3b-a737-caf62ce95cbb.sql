-- Add is_encrypted column to merchant_business_ibans for security tracking
ALTER TABLE public.merchant_business_ibans 
ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN DEFAULT false;

-- Update existing records to mark them as needing encryption
UPDATE public.merchant_business_ibans 
SET is_encrypted = false 
WHERE is_encrypted IS NULL;