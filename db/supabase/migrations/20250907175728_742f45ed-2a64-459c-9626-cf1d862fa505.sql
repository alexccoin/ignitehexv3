-- Fix hash_pin_secure function with immutable search path
CREATE OR REPLACE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  hashed_pin text;
BEGIN
  -- Validate input
  IF pin_text IS NULL OR length(pin_text) != 6 OR pin_text !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'PIN must be exactly 6 digits';
  END IF;
  
  -- Hash PIN using bcrypt for secure storage (use extensions schema explicitly)
  hashed_pin := extensions.crypt(pin_text, extensions.gen_salt('bf', 8));
  
  -- Log the PIN hash creation for security audit
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    user_uuid,
    'pin_hash_created',
    'user_profiles',
    jsonb_build_object(
      'method', 'bcrypt',
      'timestamp', now()
    ),
    get_client_ip()
  );
  
  RETURN hashed_pin;
END;
$function$;