-- Make ccoin_ledger schema robust by adding any missing columns
CREATE TABLE IF NOT EXISTS public.ccoin_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);

-- Columns
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS counterparty_user_id UUID;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS tx_id TEXT;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS from_identifier TEXT;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS to_identifier TEXT;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS amount NUMERIC;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'CCOIN';
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS network TEXT DEFAULT 'ccoin';
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'validated';
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS metadata JSONB;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS validator_node TEXT;
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS validated_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.ccoin_ledger ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- RLS
ALTER TABLE public.ccoin_ledger ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ccoin_ledger' AND policyname='Admins can manage all ccoin ledger'
  ) THEN
    CREATE POLICY "Admins can manage all ccoin ledger"
    ON public.ccoin_ledger FOR ALL
    USING (is_admin(auth.uid()))
    WITH CHECK (is_admin(auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ccoin_ledger' AND policyname='Users can insert own ledger records'
  ) THEN
    CREATE POLICY "Users can insert own ledger records"
    ON public.ccoin_ledger FOR INSERT
    WITH CHECK (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ccoin_ledger' AND policyname='Users can view own or counterparty ledger records'
  ) THEN
    CREATE POLICY "Users can view own or counterparty ledger records"
    ON public.ccoin_ledger FOR SELECT
    USING (auth.uid() = user_id OR auth.uid() = counterparty_user_id);
  END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ccoin_ledger_user_id ON public.ccoin_ledger(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ccoin_ledger_tx_id ON public.ccoin_ledger(tx_id);
CREATE INDEX IF NOT EXISTS idx_ccoin_ledger_created_at ON public.ccoin_ledger(created_at DESC);
