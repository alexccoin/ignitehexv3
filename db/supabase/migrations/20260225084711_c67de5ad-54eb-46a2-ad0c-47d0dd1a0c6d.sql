
-- Add deposit_address column to guardian_wallets for admin deposit addresses (BTC/ETH)
-- and user_external_address for user's own addresses (USDT/USDC)
ALTER TABLE public.guardian_wallets 
ADD COLUMN IF NOT EXISTS deposit_address text,
ADD COLUMN IF NOT EXISTS user_external_address text;

-- Create table for encrypted recovery keys
CREATE TABLE public.guardian_recovery_keys (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  encrypted_words text NOT NULL,
  iv text NOT NULL,
  salt text NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE public.guardian_recovery_keys ENABLE ROW LEVEL SECURITY;

-- Users can only see/manage their own recovery keys
CREATE POLICY "Users can view own recovery keys"
ON public.guardian_recovery_keys FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own recovery keys"
ON public.guardian_recovery_keys FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own recovery keys"
ON public.guardian_recovery_keys FOR UPDATE
USING (auth.uid() = user_id);

-- Admins can view all recovery keys
CREATE POLICY "Admins can view all recovery keys"
ON public.guardian_recovery_keys FOR SELECT
USING (public.is_admin(auth.uid()));

-- Allow users to update their own wallet external addresses
CREATE POLICY "Users can update own wallet addresses"
ON public.guardian_wallets FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
