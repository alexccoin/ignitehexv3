-- Add missing columns to prepaid_cards table for CCoin Bank functionality
ALTER TABLE public.prepaid_cards 
ADD COLUMN IF NOT EXISTS network TEXT DEFAULT 'ccoin',
ADD COLUMN IF NOT EXISTS full_identifier TEXT;

-- Add missing encryption columns to iban_accounts table
ALTER TABLE public.iban_accounts 
ADD COLUMN IF NOT EXISTS encrypted_iban TEXT,
ADD COLUMN IF NOT EXISTS encrypted_bic TEXT,
ADD COLUMN IF NOT EXISTS is_data_encrypted BOOLEAN DEFAULT false;

-- Create index for network lookups
CREATE INDEX IF NOT EXISTS idx_prepaid_cards_network ON public.prepaid_cards(network);
CREATE INDEX IF NOT EXISTS idx_prepaid_cards_user_network ON public.prepaid_cards(user_id, network);

-- Create index for encrypted data lookups
CREATE INDEX IF NOT EXISTS idx_iban_encrypted ON public.iban_accounts(user_id, is_data_encrypted);

-- Update RLS policies for prepaid_cards to allow admin creation
DROP POLICY IF EXISTS "Admins can insert prepaid cards" ON public.prepaid_cards;
CREATE POLICY "Admins can insert prepaid cards"
ON public.prepaid_cards FOR INSERT
WITH CHECK (is_admin(auth.uid()));

-- Update RLS policies for iban_accounts to allow admin creation
DROP POLICY IF EXISTS "Admins can insert IBAN accounts" ON public.iban_accounts;
CREATE POLICY "Admins can insert IBAN accounts"
ON public.iban_accounts FOR INSERT
WITH CHECK (is_admin(auth.uid()));