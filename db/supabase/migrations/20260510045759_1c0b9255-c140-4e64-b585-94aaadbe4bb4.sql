
CREATE TABLE public.private_str_prelisting_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  email TEXT,
  full_name TEXT,
  str_amount NUMERIC NOT NULL,
  usd_amount NUMERIC NOT NULL,
  price_per_str NUMERIC NOT NULL,
  phase TEXT NOT NULL,
  payment_status TEXT NOT NULL DEFAULT 'awaiting_payment',
  payment_crypto TEXT,
  payment_network TEXT,
  payment_amount NUMERIC,
  payment_hash TEXT,
  payment_deadline TIMESTAMPTZ,
  vesting_end_date TIMESTAMPTZ,
  referred_by TEXT,
  affiliate_code TEXT,
  admin_notes TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.private_str_prelisting_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own prelisting purchases"
  ON public.private_str_prelisting_purchases FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'seed_str_admin'::app_role));

CREATE POLICY "Users insert own prelisting purchases"
  ON public.private_str_prelisting_purchases FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own pending prelisting purchases"
  ON public.private_str_prelisting_purchases FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'seed_str_admin'::app_role))
  WITH CHECK (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'seed_str_admin'::app_role));

CREATE INDEX idx_prelisting_user ON public.private_str_prelisting_purchases(user_id);
CREATE INDEX idx_prelisting_status ON public.private_str_prelisting_purchases(payment_status);

CREATE TRIGGER trg_prelisting_updated_at
  BEFORE UPDATE ON public.private_str_prelisting_purchases
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
