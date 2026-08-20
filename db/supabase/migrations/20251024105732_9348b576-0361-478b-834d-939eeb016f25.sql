-- Fix search path for cleanup_expired_otps function
CREATE OR REPLACE FUNCTION cleanup_expired_otps()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.pin_reset_otps
  WHERE expires_at < now();
END;
$$;