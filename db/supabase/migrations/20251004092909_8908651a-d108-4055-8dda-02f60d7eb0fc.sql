-- Add voucher_type text column for Sourceless voucher type selections
ALTER TABLE public.airdrop_registrations 
ADD COLUMN IF NOT EXISTS voucher_type TEXT;

COMMENT ON COLUMN public.airdrop_registrations.voucher_type IS 'Selected voucher type for Sourceless event (e.g., str-2500)';