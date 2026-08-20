-- Update the transfer_type check constraint to include 'email' type
ALTER TABLE public.fiat_transactions DROP CONSTRAINT IF EXISTS fiat_transactions_transfer_type_check;

ALTER TABLE public.fiat_transactions 
ADD CONSTRAINT fiat_transactions_transfer_type_check 
CHECK (transfer_type IN ('network', 'account', 'email', 'sepa', 'uk_payment', 'wire', 'swift'));