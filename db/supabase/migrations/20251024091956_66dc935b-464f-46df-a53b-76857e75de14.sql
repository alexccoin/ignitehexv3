-- Create clean, non-encrypted tables for IBANs and CCoin cards, directly linked to users
-- Leaves existing encrypted tables intact

-- 0) Utility: ensure updated_at trigger function exists
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- 1) Create user_plain_ibans table
CREATE TABLE IF NOT EXISTS public.user_plain_ibans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  iban TEXT NOT NULL,
  bic TEXT NOT NULL,
  account_holder TEXT,
  country_code TEXT,
  currency TEXT NOT NULL DEFAULT 'EUR',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_user_plain_ibans_user_id ON public.user_plain_ibans(user_id);
CREATE INDEX IF NOT EXISTS idx_user_plain_ibans_status ON public.user_plain_ibans(status);

-- Enable RLS and policies
ALTER TABLE public.user_plain_ibans ENABLE ROW LEVEL SECURITY;

-- Admins can manage all
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_plain_ibans' AND policyname = 'Admins manage all plain ibans'
  ) THEN
    CREATE POLICY "Admins manage all plain ibans"
    ON public.user_plain_ibans
    FOR ALL
    USING (is_admin(auth.uid()))
    WITH CHECK (is_admin(auth.uid()));
  END IF;
END $$;

-- Users can manage their own
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_plain_ibans' AND policyname = 'Users manage own plain ibans'
  ) THEN
    CREATE POLICY "Users manage own plain ibans"
    ON public.user_plain_ibans
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Timestamp trigger
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND c.relname = 'user_plain_ibans' AND t.tgname = 'trg_user_plain_ibans_updated_at'
  ) THEN
    EXECUTE 'CREATE TRIGGER trg_user_plain_ibans_updated_at BEFORE UPDATE ON public.user_plain_ibans FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()';
  END IF;
END $$;

-- 2) Create user_plain_ccoin_cards table
CREATE TABLE IF NOT EXISTS public.user_plain_ccoin_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  card_identifier TEXT NOT NULL,
  masked_card TEXT,
  card_last4 TEXT,
  card_type TEXT NOT NULL DEFAULT 'prepaid',
  network TEXT NOT NULL DEFAULT 'ccoin',
  currency TEXT NOT NULL DEFAULT 'EUR',
  balance NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(card_identifier)
);

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_user_plain_ccoin_cards_user_id ON public.user_plain_ccoin_cards(user_id);
CREATE INDEX IF NOT EXISTS idx_user_plain_ccoin_cards_status ON public.user_plain_ccoin_cards(status);
CREATE INDEX IF NOT EXISTS idx_user_plain_ccoin_cards_network ON public.user_plain_ccoin_cards(network);

-- Enable RLS and policies
ALTER TABLE public.user_plain_ccoin_cards ENABLE ROW LEVEL SECURITY;

-- Admins can manage all
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_plain_ccoin_cards' AND policyname = 'Admins manage all plain ccoin cards'
  ) THEN
    CREATE POLICY "Admins manage all plain ccoin cards"
    ON public.user_plain_ccoin_cards
    FOR ALL
    USING (is_admin(auth.uid()))
    WITH CHECK (is_admin(auth.uid()));
  END IF;
END $$;

-- Users can manage their own
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_plain_ccoin_cards' AND policyname = 'Users manage own plain ccoin cards'
  ) THEN
    CREATE POLICY "Users manage own plain ccoin cards"
    ON public.user_plain_ccoin_cards
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Timestamp trigger
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND c.relname = 'user_plain_ccoin_cards' AND t.tgname = 'trg_user_plain_ccoin_cards_updated_at'
  ) THEN
    EXECUTE 'CREATE TRIGGER trg_user_plain_ccoin_cards_updated_at BEFORE UPDATE ON public.user_plain_ccoin_cards FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column()';
  END IF;
END $$;