-- Bulk fix: all credited applications should show payment_verified
UPDATE seed_str_applications
SET status = 'verified',
    payment_status = 'payment_verified',
    updated_at = now()
WHERE credited_at IS NOT NULL
  AND (payment_status != 'payment_verified' OR status != 'verified');

-- Create trigger to auto-finalize payment when admin credits
CREATE OR REPLACE FUNCTION public.auto_finalize_seed_str_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When credited_at is set (admin credits tokens/shares), auto-verify payment
  IF NEW.credited_at IS NOT NULL AND (OLD.credited_at IS NULL OR OLD.credited_at IS DISTINCT FROM NEW.credited_at) THEN
    NEW.status := 'verified';
    NEW.payment_status := 'payment_verified';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_finalize_seed_str_payment ON seed_str_applications;
CREATE TRIGGER trg_auto_finalize_seed_str_payment
BEFORE UPDATE ON seed_str_applications
FOR EACH ROW
EXECUTE FUNCTION public.auto_finalize_seed_str_payment();