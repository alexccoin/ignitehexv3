CREATE OR REPLACE FUNCTION public.check_domain_uniqueness()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only enforce uniqueness on INSERT or when the domain_name actually changes.
  -- This prevents bulk status updates (e.g. minting) from failing when historical
  -- duplicates already exist in the table.
  IF TG_OP = 'UPDATE' AND NEW.domain_name IS NOT DISTINCT FROM OLD.domain_name THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM str_domains
    WHERE LOWER(domain_name) = LOWER(NEW.domain_name)
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) THEN
    RAISE EXCEPTION 'Domain name % already exists. Each str.domain must be unique.', NEW.domain_name;
  END IF;

  RETURN NEW;
END;
$function$;