-- Add event_type and voucher_id columns to airdrop_registrations table
ALTER TABLE public.airdrop_registrations 
ADD COLUMN IF NOT EXISTS event_type TEXT,
ADD COLUMN IF NOT EXISTS voucher_id UUID REFERENCES public.voucher_redemptions(id);

-- Add index for better query performance
CREATE INDEX IF NOT EXISTS idx_airdrop_registrations_voucher_id ON public.airdrop_registrations(voucher_id);

COMMENT ON COLUMN public.airdrop_registrations.event_type IS 'Event type: sourceless or sasp';
COMMENT ON COLUMN public.airdrop_registrations.voucher_id IS 'Optional reference to voucher redemption';