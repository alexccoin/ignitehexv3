-- Fix digest function calls to use proper text casting
CREATE OR REPLACE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  salt text;
  hash_input text;
  iterations int := 10000;
BEGIN
  -- Generate salt using proper text casting
  salt := encode(extensions.digest(user_uuid::text || extract(epoch from now())::text || random()::text, 'sha256'::text), 'hex');
  hash_input := pin_text || salt || iterations::text;
  RETURN iterations::text || '$' || salt || '$' || encode(extensions.digest(hash_input, 'sha256'::text), 'hex');
END;
$function$;

CREATE OR REPLACE FUNCTION public.verify_pin_secure(pin_text text, stored_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  hash_parts text[];
  iterations int;
  salt text;
  stored_hash_value text;
  calculated_hash text;
BEGIN
  hash_parts := string_to_array(stored_hash, '$');
  
  IF array_length(hash_parts, 1) != 3 THEN
    RETURN false;
  END IF;
  
  iterations := hash_parts[1]::int;
  salt := hash_parts[2];
  stored_hash_value := hash_parts[3];
  
  -- Use proper text casting for digest function
  calculated_hash := encode(extensions.digest(pin_text || salt || iterations::text, 'sha256'::text), 'hex');
  
  RETURN calculated_hash = stored_hash_value;
END;
$function$;