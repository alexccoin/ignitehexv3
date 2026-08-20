
-- SAFE round administration & subscription tracking
-- ---------------------------------------------------------------
-- 1) safe_admins: users granted access to the SAFE admin page
--    (in addition to anyone with role 'admin' in user_roles)
CREATE TABLE IF NOT EXISTS public.safe_admins (
  user_id UUID NOT NULL PRIMARY KEY,
  full_name TEXT,
  granted_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.safe_admins TO authenticated;
GRANT ALL ON public.safe_admins TO service_role;

ALTER TABLE public.safe_admins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view safe_admins"
  ON public.safe_admins FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role) OR user_id = auth.uid());

CREATE POLICY "Admins can manage safe_admins"
  ON public.safe_admins FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- Helper function: true if user is admin OR present in safe_admins
CREATE OR REPLACE FUNCTION public.is_safe_admin(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = 'admin'::app_role
  ) OR EXISTS (
    SELECT 1 FROM public.safe_admins WHERE user_id = _user_id
  );
$$;

-- Seed Thomas Wenz as full SAFE admin
INSERT INTO public.safe_admins (user_id, full_name)
VALUES ('fcf333e7-10e7-4d26-818f-31159f325c73', 'Thomas Wenz')
ON CONFLICT (user_id) DO NOTHING;

-- ---------------------------------------------------------------
-- 2) safe_purchases: SAFE round subscriptions for SourceLess Inc.
CREATE TABLE IF NOT EXISTS public.safe_purchases (
  id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,                          -- optional, if subscriber is a logged-in user
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT NOT NULL,
  shares INTEGER NOT NULL,
  bonus_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
  bonus_shares INTEGER NOT NULL DEFAULT 0,
  total_shares INTEGER NOT NULL,
  price_per_share_usd NUMERIC(12,2) NOT NULL DEFAULT 20,
  total_usd NUMERIC(14,2) NOT NULL,
  crypto TEXT NOT NULL,                  -- 'BTC' | 'ETH'
  tx_hash TEXT NOT NULL,
  pep_declared BOOLEAN NOT NULL DEFAULT false,
  presenter_full_name TEXT,              -- WHO presented this link (commission tracking)
  presenter_email TEXT,
  presenter_phone TEXT,
  presenter_ref TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | credited | rejected
  credited_shares INTEGER,
  credited_at TIMESTAMPTZ,
  credited_by UUID,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.safe_purchases TO anon;            -- public form needs to insert
GRANT SELECT, INSERT, UPDATE ON public.safe_purchases TO authenticated;
GRANT INSERT ON public.safe_purchases TO anon;
GRANT ALL ON public.safe_purchases TO service_role;

ALTER TABLE public.safe_purchases ENABLE ROW LEVEL SECURITY;

-- Anyone (incl. anon) can submit a subscription
CREATE POLICY "Anyone can submit SAFE subscription"
  ON public.safe_purchases FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Subscriber sees their own
CREATE POLICY "Users see own SAFE subscriptions"
  ON public.safe_purchases FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- SAFE admins (admin role or safe_admins entry) see all
CREATE POLICY "SAFE admins see all"
  ON public.safe_purchases FOR SELECT TO authenticated
  USING (public.is_safe_admin(auth.uid()));

-- SAFE admins can update (credit / reject / annotate)
CREATE POLICY "SAFE admins manage subscriptions"
  ON public.safe_purchases FOR UPDATE TO authenticated
  USING (public.is_safe_admin(auth.uid()))
  WITH CHECK (public.is_safe_admin(auth.uid()));

-- Updated-at trigger
CREATE OR REPLACE FUNCTION public.set_safe_purchases_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_safe_purchases_updated_at ON public.safe_purchases;
CREATE TRIGGER trg_safe_purchases_updated_at
  BEFORE UPDATE ON public.safe_purchases
  FOR EACH ROW EXECUTE FUNCTION public.set_safe_purchases_updated_at();

CREATE INDEX IF NOT EXISTS idx_safe_purchases_status ON public.safe_purchases(status);
CREATE INDEX IF NOT EXISTS idx_safe_purchases_presenter ON public.safe_purchases(presenter_full_name);
CREATE INDEX IF NOT EXISTS idx_safe_purchases_created_at ON public.safe_purchases(created_at DESC);
