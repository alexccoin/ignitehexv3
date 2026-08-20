
-- Fix search_path for auto_mint_profile_domain function
CREATE OR REPLACE FUNCTION auto_mint_profile_domain()
RETURNS TRIGGER AS $$
DECLARE
  clean_domain_name TEXT;
BEGIN
  -- If str_domain_username is set, ensure a minted domain exists
  IF NEW.str_domain_username IS NOT NULL 
     AND NEW.str_domain_username != '' 
     AND LOWER(NEW.str_domain_username) NOT IN ('to be updated', 'tobeupdated', 'tbd', 'n/a', 'na', 'none', 'null', 'test')
     AND LOWER(NEW.str_domain_username) NOT LIKE '%update%'
  THEN
    clean_domain_name := LOWER(REPLACE(REPLACE(NEW.str_domain_username, 'str.', ''), ' ', ''));
    
    -- Check length requirements (3-63 chars)
    IF LENGTH(clean_domain_name) >= 3 AND LENGTH(clean_domain_name) <= 63 THEN
      -- Only insert if domain doesn't already exist
      IF NOT EXISTS (SELECT 1 FROM public.str_domains WHERE LOWER(domain_name) = clean_domain_name) THEN
        INSERT INTO public.str_domains (user_id, domain_name, domain_type, status, minted_at)
        VALUES (NEW.user_id, clean_domain_name, 'personal', 'minted', NOW());
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
