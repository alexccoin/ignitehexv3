-- Create/update timestamp trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public';

-- Prepaid cards table
CREATE TABLE IF NOT EXISTS public.prepaid_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  card_type TEXT NOT NULL,
  currency TEXT NOT NULL,
  balance NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  card_last4 TEXT NOT NULL,
  masked_card TEXT NOT NULL,
  issuer TEXT DEFAULT 'ARESfin',
  expiry_date DATE,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.prepaid_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Admins can manage all prepaid cards"
ON public.prepaid_cards FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

CREATE POLICY IF NOT EXISTS "Users can view their own prepaid cards"
ON public.prepaid_cards FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can insert their own prepaid cards"
ON public.prepaid_cards FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can update their own prepaid cards"
ON public.prepaid_cards FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP TRIGGER IF EXISTS trg_prepaid_cards_updated_at ON public.prepaid_cards;
CREATE TRIGGER trg_prepaid_cards_updated_at
BEFORE UPDATE ON public.prepaid_cards
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Currency exchanges table
CREATE TABLE IF NOT EXISTS public.currency_exchanges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  from_currency TEXT NOT NULL,
  to_currency TEXT NOT NULL,
  from_amount NUMERIC NOT NULL,
  to_amount NUMERIC NOT NULL,
  exchange_rate NUMERIC NOT NULL,
  fee_amount NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'completed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.currency_exchanges ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Admins can manage all currency exchanges"
ON public.currency_exchanges FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

CREATE POLICY IF NOT EXISTS "Users can view their own currency exchanges"
ON public.currency_exchanges FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can insert their own currency exchanges"
ON public.currency_exchanges FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can update their own currency exchanges"
ON public.currency_exchanges FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP TRIGGER IF EXISTS trg_currency_exchanges_updated_at ON public.currency_exchanges;
CREATE TRIGGER trg_currency_exchanges_updated_at
BEFORE UPDATE ON public.currency_exchanges
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Cross-border payments table
CREATE TABLE IF NOT EXISTS public.cross_border_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  recipient_name TEXT,
  amount NUMERIC NOT NULL,
  currency TEXT NOT NULL,
  payment_rail TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  reference TEXT,
  fee_amount NUMERIC NOT NULL DEFAULT 0,
  sender_country TEXT,
  receiver_country TEXT,
  compliance_score NUMERIC,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.cross_border_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Admins can manage all cross-border payments"
ON public.cross_border_payments FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

CREATE POLICY IF NOT EXISTS "Users can view their own cross-border payments"
ON public.cross_border_payments FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can insert their own cross-border payments"
ON public.cross_border_payments FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can update their own cross-border payments"
ON public.cross_border_payments FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP TRIGGER IF EXISTS trg_cross_border_payments_updated_at ON public.cross_border_payments;
CREATE TRIGGER trg_cross_border_payments_updated_at
BEFORE UPDATE ON public.cross_border_payments
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();