
CREATE TABLE IF NOT EXISTS public.card_shipping_details (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  card_type TEXT NOT NULL CHECK (card_type IN ('physical', 'ccoin')),
  full_name TEXT NOT NULL,
  address_line1 TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT NOT NULL,
  state_province TEXT,
  postal_code TEXT NOT NULL,
  country TEXT NOT NULL,
  phone TEXT,
  status TEXT NOT NULL DEFAULT 'pending_shipping',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE (user_id, card_type)
);

ALTER TABLE public.card_shipping_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own shipping details"
  ON public.card_shipping_details
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own shipping details"
  ON public.card_shipping_details
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own shipping details"
  ON public.card_shipping_details
  FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all shipping details"
  ON public.card_shipping_details
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  );

CREATE OR REPLACE FUNCTION public.update_card_shipping_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_card_shipping_details_updated_at
  BEFORE UPDATE ON public.card_shipping_details
  FOR EACH ROW
  EXECUTE FUNCTION public.update_card_shipping_updated_at();
