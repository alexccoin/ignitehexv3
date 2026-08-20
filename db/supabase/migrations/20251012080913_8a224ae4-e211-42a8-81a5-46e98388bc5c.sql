-- Create ccos_purchases table for CCOS token sale management
CREATE TABLE IF NOT EXISTS public.ccos_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  email_address TEXT NOT NULL,
  str_domain TEXT,
  package_amount_usd NUMERIC NOT NULL,
  transaction_hash TEXT,
  payment_method TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ccos_purchases ENABLE ROW LEVEL SECURITY;

-- Users can insert their own purchases
CREATE POLICY "Users can insert own CCOS purchases"
ON public.ccos_purchases
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Users can view their own purchases
CREATE POLICY "Users can view own CCOS purchases"
ON public.ccos_purchases
FOR SELECT
TO authenticated
USING (auth.uid() = user_id OR user_id IS NULL);

-- Admins can view all purchases
CREATE POLICY "Admins can view all CCOS purchases"
ON public.ccos_purchases
FOR SELECT
TO authenticated
USING (is_admin(auth.uid()));

-- Admins can update all purchases
CREATE POLICY "Admins can update all CCOS purchases"
ON public.ccos_purchases
FOR UPDATE
TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Create index for faster queries
CREATE INDEX idx_ccos_purchases_user_id ON public.ccos_purchases(user_id);
CREATE INDEX idx_ccos_purchases_status ON public.ccos_purchases(status);
CREATE INDEX idx_ccos_purchases_created_at ON public.ccos_purchases(created_at DESC);