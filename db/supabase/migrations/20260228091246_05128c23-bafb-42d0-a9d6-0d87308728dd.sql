
CREATE TABLE public.private_str_ipo_purchases (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  full_name TEXT,
  str_amount NUMERIC NOT NULL,
  usd_amount NUMERIC NOT NULL,
  price_per_str NUMERIC NOT NULL,
  payment_crypto TEXT,
  payment_amount NUMERIC,
  payment_hash TEXT,
  payment_status TEXT NOT NULL DEFAULT 'awaiting_payment',
  payment_deadline TIMESTAMPTZ,
  phase TEXT NOT NULL DEFAULT 'phase1',
  affiliate_code TEXT,
  referred_by TEXT,
  admin_notes TEXT,
  processed_at TIMESTAMPTZ,
  processed_by UUID,
  vesting_end_date TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.private_str_ipo_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own ipo purchases"
  ON public.private_str_ipo_purchases FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own ipo purchases"
  ON public.private_str_ipo_purchases FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own ipo purchases"
  ON public.private_str_ipo_purchases FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all ipo purchases"
  ON public.private_str_ipo_purchases FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'super_admin')
    )
  );

CREATE POLICY "Admins can update all ipo purchases"
  ON public.private_str_ipo_purchases FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
      AND profiles.role IN ('admin', 'super_admin')
    )
  );

CREATE TRIGGER update_private_str_ipo_purchases_updated_at
  BEFORE UPDATE ON public.private_str_ipo_purchases
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
