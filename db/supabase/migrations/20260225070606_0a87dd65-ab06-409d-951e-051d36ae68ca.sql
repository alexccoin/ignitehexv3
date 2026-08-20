
-- Create IPO listing requests table
CREATE TABLE public.ipo_listing_requests (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  address TEXT,
  share_type TEXT NOT NULL CHECK (share_type IN ('seed_private_sale', 'ssi', 'pre_ipo')),
  number_of_shares INTEGER NOT NULL CHECK (number_of_shares > 0),
  price_per_share NUMERIC NOT NULL DEFAULT 91.3,
  total_usd_value NUMERIC NOT NULL,
  receiving_currency TEXT NOT NULL CHECK (receiving_currency IN ('USD', 'EUR')),
  iban TEXT NOT NULL,
  bank_name TEXT NOT NULL,
  bank_swift TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  admin_notes TEXT,
  processed_by TEXT,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ipo_listing_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own requests
CREATE POLICY "Users can view own IPO requests"
  ON public.ipo_listing_requests FOR SELECT
  USING (auth.uid() = user_id);

-- Users can create their own requests
CREATE POLICY "Users can create own IPO requests"
  ON public.ipo_listing_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own pending requests
CREATE POLICY "Users can update own pending IPO requests"
  ON public.ipo_listing_requests FOR UPDATE
  USING (auth.uid() = user_id AND status = 'pending');

-- Admins can view all requests
CREATE POLICY "Admins can view all IPO requests"
  ON public.ipo_listing_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role IN ('admin', 'seed_str_admin')
    )
  );

-- Admins can update all requests
CREATE POLICY "Admins can update all IPO requests"
  ON public.ipo_listing_requests FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role IN ('admin', 'seed_str_admin')
    )
  );

-- Seed STR admins can also view all
CREATE POLICY "Seed STR admins can view all IPO requests"
  ON public.ipo_listing_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'seed_str_admin'
    )
  );

-- Auto-update updated_at
CREATE TRIGGER update_ipo_listing_requests_updated_at
  BEFORE UPDATE ON public.ipo_listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
