ALTER TABLE public.missing_asset_reports 
  ADD COLUMN IF NOT EXISTS transaction_hash text,
  ADD COLUMN IF NOT EXISTS claimed_amounts jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS resolution_log jsonb DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.missing_asset_reports.transaction_hash IS 'User-submitted payment/voucher transaction hash for verification';
COMMENT ON COLUMN public.missing_asset_reports.claimed_amounts IS 'User-claimed token amounts e.g. {"str": 1000, "ccos": 50}';
COMMENT ON COLUMN public.missing_asset_reports.resolution_log IS 'Auto-resolver actions log with before/after snapshots';