
-- Create table for private digital shares purchases
CREATE TABLE public.private_digital_shares_purchases (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  full_name TEXT,
  shares_quantity INTEGER NOT NULL,
  price_per_share NUMERIC NOT NULL DEFAULT 9.00,
  total_usd NUMERIC NOT NULL,
  payment_crypto TEXT,
  payment_amount NUMERIC,
  payment_hash TEXT,
  payment_status TEXT NOT NULL DEFAULT 'awaiting_payment',
  payment_deadline TIMESTAMPTZ,
  wnft_status TEXT NOT NULL DEFAULT 'pending',
  wnft_redeemed_at TIMESTAMPTZ,
  referred_by TEXT,
  affiliate_code TEXT,
  admin_notes TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.private_digital_shares_purchases ENABLE ROW LEVEL SECURITY;

-- Users can view their own purchases
CREATE POLICY "Users can view own digital share purchases"
ON public.private_digital_shares_purchases
FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own purchases
CREATE POLICY "Users can create own digital share purchases"
ON public.private_digital_shares_purchases
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own awaiting_payment purchases
CREATE POLICY "Users can update own pending digital share purchases"
ON public.private_digital_shares_purchases
FOR UPDATE USING (auth.uid() = user_id AND payment_status IN ('awaiting_payment', 'payment_submitted'));

-- Admins can view all
CREATE POLICY "Admins can view all digital share purchases"
ON public.private_digital_shares_purchases
FOR SELECT USING (public.has_role(auth.uid(), 'admin'));

-- Admins can update all
CREATE POLICY "Admins can update all digital share purchases"
ON public.private_digital_shares_purchases
FOR UPDATE USING (public.has_role(auth.uid(), 'admin'));

-- Timestamp trigger
CREATE TRIGGER update_digital_shares_updated_at
BEFORE UPDATE ON public.private_digital_shares_purchases
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
