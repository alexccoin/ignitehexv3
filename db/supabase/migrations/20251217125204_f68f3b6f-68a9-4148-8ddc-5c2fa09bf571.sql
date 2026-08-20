-- Create table for ARSS token purchases
CREATE TABLE public.arss_token_purchases (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  full_name TEXT,
  usd_amount NUMERIC NOT NULL CHECK (usd_amount >= 100 AND usd_amount <= 100000),
  crypto_amount NUMERIC NOT NULL,
  crypto_currency TEXT NOT NULL CHECK (crypto_currency IN ('BTC', 'ETH')),
  arss_amount NUMERIC NOT NULL,
  bonus_percent INTEGER DEFAULT 0,
  bonus_amount NUMERIC DEFAULT 0,
  total_arss_amount NUMERIC NOT NULL,
  arss_price_at_purchase NUMERIC NOT NULL,
  crypto_price_at_purchase NUMERIC NOT NULL,
  payment_address TEXT NOT NULL,
  transaction_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'credited', 'cancelled', 'refunded')),
  admin_notes TEXT,
  credited_at TIMESTAMP WITH TIME ZONE,
  credited_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.arss_token_purchases ENABLE ROW LEVEL SECURITY;

-- Users can view their own purchases
CREATE POLICY "Users can view their own purchases"
ON public.arss_token_purchases
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own purchases
CREATE POLICY "Users can insert their own purchases"
ON public.arss_token_purchases
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own pending purchases (to add transaction hash)
CREATE POLICY "Users can update their own pending purchases"
ON public.arss_token_purchases
FOR UPDATE
USING (auth.uid() = user_id AND status = 'pending');

-- Create index for faster lookups
CREATE INDEX idx_arss_purchases_user_id ON public.arss_token_purchases(user_id);
CREATE INDEX idx_arss_purchases_status ON public.arss_token_purchases(status);
CREATE INDEX idx_arss_purchases_created_at ON public.arss_token_purchases(created_at DESC);