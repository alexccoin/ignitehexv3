-- Fix search path for domain update function - use CASCADE
DROP FUNCTION IF EXISTS update_str_domains_updated_at() CASCADE;

CREATE OR REPLACE FUNCTION update_str_domains_updated_at()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER trigger_update_str_domains_updated_at
  BEFORE UPDATE ON public.str_domains
  FOR EACH ROW
  EXECUTE FUNCTION update_str_domains_updated_at();