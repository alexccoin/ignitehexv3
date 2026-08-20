
-- Table to store IBAN data confirmation/rejection from CCoin Bank members
CREATE TABLE public.iban_data_confirmations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  city TEXT,
  postal_code TEXT,
  country TEXT,
  str_domain TEXT,
  confirmation_status TEXT NOT NULL DEFAULT 'pending', -- pending, confirmed, rejected
  wants_iban BOOLEAN DEFAULT true,
  rejection_reason TEXT,
  admin_notes TEXT,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE public.iban_data_confirmations ENABLE ROW LEVEL SECURITY;

-- Users can view their own confirmation
CREATE POLICY "Users can view own iban confirmation"
ON public.iban_data_confirmations
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Users can insert their own confirmation
CREATE POLICY "Users can insert own iban confirmation"
ON public.iban_data_confirmations
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can update their own confirmation
CREATE POLICY "Users can update own iban confirmation"
ON public.iban_data_confirmations
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-- Admins can view all confirmations
CREATE POLICY "Admins can view all iban confirmations"
ON public.iban_data_confirmations
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- Admins can update all confirmations
CREATE POLICY "Admins can update all iban confirmations"
ON public.iban_data_confirmations
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- Trigger for updated_at
CREATE TRIGGER update_iban_data_confirmations_updated_at
BEFORE UPDATE ON public.iban_data_confirmations
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
