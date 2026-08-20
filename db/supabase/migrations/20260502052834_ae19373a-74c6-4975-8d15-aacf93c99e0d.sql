-- str.dome shares + SLNN e-SIM Founder Package Requests
CREATE TABLE public.str_dome_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  str_dome_username text NOT NULL,
  account_email text NOT NULL,
  delivery_email text NOT NULL,
  esim_country text NOT NULL,
  package_name text NOT NULL,
  package_price_usd numeric NOT NULL,
  notes text,
  status text NOT NULL DEFAULT 'pending',
  admin_notes text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT str_dome_requests_status_check CHECK (status IN ('pending','approved','rejected','fulfilled','cancelled'))
);

CREATE INDEX idx_str_dome_requests_user_id ON public.str_dome_requests(user_id);
CREATE INDEX idx_str_dome_requests_status ON public.str_dome_requests(status);
CREATE INDEX idx_str_dome_requests_created_at ON public.str_dome_requests(created_at DESC);

ALTER TABLE public.str_dome_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own requests
CREATE POLICY "Users view own str_dome requests"
  ON public.str_dome_requests FOR SELECT
  USING (auth.uid() = user_id);

-- Users can create their own requests
CREATE POLICY "Users create own str_dome requests"
  ON public.str_dome_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Admins can view all
CREATE POLICY "Admins view all str_dome requests"
  ON public.str_dome_requests FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'::app_role));

-- Admins can update all
CREATE POLICY "Admins update str_dome requests"
  ON public.str_dome_requests FOR UPDATE
  USING (public.has_role(auth.uid(), 'admin'::app_role));

-- updated_at trigger
CREATE TRIGGER update_str_dome_requests_updated_at
  BEFORE UPDATE ON public.str_dome_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();