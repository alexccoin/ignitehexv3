-- Create CCoin ledger table for network transaction validation
CREATE TABLE IF NOT EXISTS public.ccoin_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tx_id TEXT NOT NULL UNIQUE,
  user_id UUID NOT NULL,
  counterparty_user_id UUID NULL,
  from_identifier TEXT NOT NULL,
  to_identifier TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  currency TEXT NOT NULL DEFAULT 'CCOIN',
  network TEXT NOT NULL DEFAULT 'ccoin',
  status TEXT NOT NULL DEFAULT 'validated',
  metadata JSONB NULL,
  validator_node TEXT NULL,
  validated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ccoin_ledger ENABLE ROW LEVEL SECURITY;

-- Policies
DO $$ BEGIN
  -- Admins can manage all
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ccoin_ledger' AND policyname='Admins can manage all ccoin ledger'
  ) THEN
    CREATE POLICY "Admins can manage all ccoin ledger"
    ON public.ccoin_ledger
    FOR ALL
    USING (is_admin(auth.uid()))
    WITH CHECK (is_admin(auth.uid()));
  END IF;

  -- Users can insert their own transactions
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ccoin_ledger' AND policyname='Users can insert own ledger records'
  ) THEN
    CREATE POLICY "Users can insert own ledger records"
    ON public.ccoin_ledger
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);
  END IF;

  -- Users can view records where they are sender or counterparty
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='ccoin_ledger' AND policyname='Users can view own or counterparty ledger records'
  ) THEN
    CREATE POLICY "Users can view own or counterparty ledger records"
    ON public.ccoin_ledger
    FOR SELECT
    USING (auth.uid() = user_id OR auth.uid() = counterparty_user_id);
  END IF;
END $$;

-- Helpful indexes
CREATE INDEX IF NOT EXISTS idx_ccoin_ledger_user_id ON public.ccoin_ledger(user_id);
CREATE INDEX IF NOT EXISTS idx_ccoin_ledger_tx_id ON public.ccoin_ledger(tx_id);
CREATE INDEX IF NOT EXISTS idx_ccoin_ledger_created_at ON public.ccoin_ledger(created_at DESC);
