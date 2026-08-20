-- Security linter fix: set immutable search_path on trigger function
-- (prevents Function Search Path Mutable warning)

CREATE OR REPLACE FUNCTION public.update_domain_wallets_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;