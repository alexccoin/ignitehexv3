
ALTER TABLE public.v2_asset_claims
  ADD COLUMN IF NOT EXISTS platform text,
  ADD COLUMN IF NOT EXISTS asset_type text,
  ADD COLUMN IF NOT EXISTS tx_hash text,
  ADD COLUMN IF NOT EXISTS tx_currency text,
  ADD COLUMN IF NOT EXISTS wallet_address text,
  ADD COLUMN IF NOT EXISTS duplicate_of uuid REFERENCES public.v2_asset_claims(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS flagged_reason text;

CREATE UNIQUE INDEX IF NOT EXISTS v2_asset_claims_txhash_unique
  ON public.v2_asset_claims (lower(tx_hash))
  WHERE tx_hash IS NOT NULL AND tx_hash <> '' AND status <> 'rejected';

CREATE INDEX IF NOT EXISTS v2_asset_claims_status_idx ON public.v2_asset_claims (status, created_at DESC);

CREATE OR REPLACE FUNCTION public.v2_flag_duplicate_asset_claim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  dup_id uuid;
BEGIN
  IF NEW.tx_hash IS NOT NULL AND NEW.tx_hash <> '' THEN
    SELECT id INTO dup_id
    FROM public.v2_asset_claims
    WHERE id <> NEW.id
      AND lower(tx_hash) = lower(NEW.tx_hash)
    ORDER BY created_at ASC
    LIMIT 1;

    IF dup_id IS NOT NULL THEN
      NEW.duplicate_of := dup_id;
      NEW.flagged_reason := 'Duplicate transaction hash already declared';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS v2_asset_claims_dup_check ON public.v2_asset_claims;
CREATE TRIGGER v2_asset_claims_dup_check
BEFORE INSERT ON public.v2_asset_claims
FOR EACH ROW EXECUTE FUNCTION public.v2_flag_duplicate_asset_claim();
