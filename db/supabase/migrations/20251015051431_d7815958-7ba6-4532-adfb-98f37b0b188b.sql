-- Create addendum table for user profiles to store extended fields
CREATE TABLE IF NOT EXISTS public.user_profile_addendum (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE,
  -- Banking preferences
  iban_currency_preferences TEXT[] DEFAULT '{}',
  iban_country_code TEXT,
  default_card_network TEXT, -- e.g., 'visa' | 'ccoin'
  -- Compliance and KYC
  kyc_status TEXT DEFAULT 'pending',
  tax_residency_country_code TEXT,
  date_of_birth DATE,
  compliance_flags JSONB DEFAULT '{}'::jsonb,
  -- Contact/address extras
  phone_number TEXT,
  address_line2 TEXT,
  -- Cards and limits
  card_limits JSONB DEFAULT '{}'::jsonb,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_addendum_user
    FOREIGN KEY (user_id)
    REFERENCES public.user_profiles (user_id)
    ON DELETE CASCADE
);

-- Enable RLS
ALTER TABLE public.user_profile_addendum ENABLE ROW LEVEL SECURITY;

-- Policies: Admins manage all
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' AND tablename='user_profile_addendum' AND policyname='Admins manage addendum'
  ) THEN
    CREATE POLICY "Admins manage addendum"
    ON public.user_profile_addendum
    FOR ALL
    USING (is_admin(auth.uid()))
    WITH CHECK (is_admin(auth.uid()));
  END IF;
END $$;

-- Policies: Users can view/update/insert their own
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' AND tablename='user_profile_addendum' AND policyname='Users select own addendum'
  ) THEN
    CREATE POLICY "Users select own addendum"
    ON public.user_profile_addendum
    FOR SELECT
    USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' AND tablename='user_profile_addendum' AND policyname='Users insert own addendum'
  ) THEN
    CREATE POLICY "Users insert own addendum"
    ON public.user_profile_addendum
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname='public' AND tablename='user_profile_addendum' AND policyname='Users update own addendum'
  ) THEN
    CREATE POLICY "Users update own addendum"
    ON public.user_profile_addendum
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_profile_addendum_user_id ON public.user_profile_addendum(user_id);

-- Auto-update updated_at
CREATE TRIGGER update_user_profile_addendum_updated_at
BEFORE UPDATE ON public.user_profile_addendum
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Seed addendum rows for existing users
INSERT INTO public.user_profile_addendum (user_id)
SELECT up.user_id
FROM public.user_profiles up
ON CONFLICT (user_id) DO NOTHING;
