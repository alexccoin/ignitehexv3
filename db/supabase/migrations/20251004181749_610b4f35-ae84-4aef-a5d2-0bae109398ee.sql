-- Create STARW purchases table
CREATE TABLE IF NOT EXISTS public.starw_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  email_address TEXT NOT NULL,
  str_domain TEXT,
  wallet_address TEXT,
  node_count INTEGER NOT NULL DEFAULT 1,
  total_cost NUMERIC NOT NULL,
  arss_bonus TEXT NOT NULL,
  stage INTEGER NOT NULL,
  payment_method TEXT,
  payment_info JSONB,
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.starw_purchases ENABLE ROW LEVEL SECURITY;

-- Users can insert their own purchases
CREATE POLICY "Users can insert own STARW purchases"
  ON public.starw_purchases
  FOR INSERT
  WITH CHECK (auth.uid() = user_id OR auth.uid() IS NULL);

-- Users can view their own purchases
CREATE POLICY "Users can view own STARW purchases"
  ON public.starw_purchases
  FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can view all purchases
CREATE POLICY "Admins can view all STARW purchases"
  ON public.starw_purchases
  FOR SELECT
  USING (is_admin(auth.uid()));

-- Admins can update all purchases
CREATE POLICY "Admins can update all STARW purchases"
  ON public.starw_purchases
  FOR UPDATE
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- Create index for faster queries
CREATE INDEX idx_starw_purchases_status ON public.starw_purchases(status);
CREATE INDEX idx_starw_purchases_created_at ON public.starw_purchases(created_at DESC);
CREATE INDEX idx_starw_purchases_user_id ON public.starw_purchases(user_id);

-- Add trigger for updated_at
CREATE TRIGGER update_starw_purchases_updated_at
  BEFORE UPDATE ON public.starw_purchases
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();