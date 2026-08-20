ALTER TABLE public.v2_accounts
  ADD COLUMN IF NOT EXISTS account_mode TEXT NOT NULL DEFAULT 'regulated',
  ADD COLUMN IF NOT EXISTS account_mode_selected_at TIMESTAMPTZ;

DO $$ BEGIN
  ALTER TABLE public.v2_accounts
    ADD CONSTRAINT v2_accounts_account_mode_check
    CHECK (account_mode IN ('regulated','decentralised'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;