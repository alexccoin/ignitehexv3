-- Add new columns to voucher_redemptions table for card payments
ALTER TABLE public.voucher_redemptions 
ADD COLUMN confirmation_number TEXT,
ADD COLUMN amount TEXT;

-- Update the payment_type check constraint to include 'card'
ALTER TABLE public.voucher_redemptions 
DROP CONSTRAINT voucher_redemptions_payment_type_check;

ALTER TABLE public.voucher_redemptions 
ADD CONSTRAINT voucher_redemptions_payment_type_check 
CHECK (payment_type IN ('crypto', 'bank', 'card'));