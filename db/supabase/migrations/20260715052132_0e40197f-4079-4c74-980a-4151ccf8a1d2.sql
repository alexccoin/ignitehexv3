
-- CCoin Bank rails: add rail + CCOS fee tracking to pending transfers and exchanges
ALTER TABLE public.pending_transfers_treasury
  ADD COLUMN IF NOT EXISTS rail text,
  ADD COLUMN IF NOT EXISTS fee_ccos numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fee_ledger_id uuid;

ALTER TABLE public.currency_exchanges
  ADD COLUMN IF NOT EXISTS rail text,
  ADD COLUMN IF NOT EXISTS fee_ccos numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fee_ledger_id uuid;

-- Ensure new exchanges default to pending
ALTER TABLE public.currency_exchanges
  ALTER COLUMN status SET DEFAULT 'pending';
