-- Fix the check_domain_uniqueness function with proper search_path
CREATE OR REPLACE FUNCTION check_domain_uniqueness()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if domain already exists (case-insensitive)
  IF EXISTS (
    SELECT 1 FROM str_domains 
    WHERE LOWER(domain_name) = LOWER(NEW.domain_name)
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) THEN
    RAISE EXCEPTION 'Domain name % already exists. Each str.domain must be unique.', NEW.domain_name;
  END IF;
  
  RETURN NEW;
END;
$$;