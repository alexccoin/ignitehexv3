-- Fix hash_pin_secure function signature issue
DROP FUNCTION IF EXISTS hash_pin_secure(text);

CREATE OR REPLACE FUNCTION hash_pin_secure(input_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Validate PIN format (4-8 digits)
  IF input_pin !~ '^[0-9]{4,8}$' THEN
    RAISE EXCEPTION 'Invalid PIN format. Must be 4-8 digits only.';
  END IF;
  
  -- Generate secure hash using pgcrypto
  RETURN crypt(input_pin, gen_salt('bf', 12));
END;
$$;

-- Fix verify_pin_secure function signature
DROP FUNCTION IF EXISTS verify_pin_secure(text, text);

CREATE OR REPLACE FUNCTION verify_pin_secure(input_pin text, stored_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Validate inputs
  IF input_pin IS NULL OR stored_hash IS NULL THEN
    RETURN false;
  END IF;
  
  -- Verify PIN format
  IF input_pin !~ '^[0-9]{4,8}$' THEN
    RETURN false;
  END IF;
  
  -- Verify hash using pgcrypto
  RETURN (crypt(input_pin, stored_hash) = stored_hash);
END;
$$;

-- Test the functions
SELECT 'Security functions fixed successfully' as status;