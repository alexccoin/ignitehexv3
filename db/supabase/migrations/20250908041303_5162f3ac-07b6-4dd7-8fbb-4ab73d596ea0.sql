-- Fix all functions to have proper search paths
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  rate_limit_result jsonb;
  result jsonb;
BEGIN
  -- Check rate limit with progressive delays
  SELECT check_rate_limit_with_progressive_delay(user_uuid, client_ip, 'wallet_pin', 5, 60)
  INTO rate_limit_result;
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip, 'wallet_pin', false, 
      jsonb_build_object('reason', rate_limit_result->>'reason', 'retry_after', rate_limit_result->>'retry_after'));
    RETURN jsonb_build_object(
      'success', false,
      'error', rate_limit_result->>'reason',
      'message', CASE 
        WHEN rate_limit_result->>'reason' = 'rate_limited' THEN 'Too many failed attempts. Please try again later.'
        WHEN rate_limit_result->>'reason' = 'progressive_delay' THEN 'Please wait ' || (rate_limit_result->>'retry_after') || ' seconds before trying again.'
        ELSE 'Rate limit exceeded.'
      END,
      'retry_after', rate_limit_result->>'retry_after'
    );
  END IF;

  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  IF stored_pin_hash IS NULL THEN
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN set for this user.'
    );
  END IF;

  -- Validate PIN with bcrypt or legacy sha256
  IF stored_pin_hash LIKE '$2%' THEN
    is_valid := public.verify_password(input_pin, stored_pin_hash);
  ELSE
    is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  END IF;

  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success)
  VALUES (user_uuid, client_ip, 'wallet_pin', is_valid);

  IF is_valid THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'PIN validated successfully.'
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin',
      'message', 'Invalid PIN provided.'
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.hash_password(plain_password text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- Use pgcrypto from extensions schema for password hashing
  RETURN extensions.crypt(plain_password, extensions.gen_salt('bf', 8));
END;
$function$;

CREATE OR REPLACE FUNCTION public.hash_existing_position_passwords()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  UPDATE founder_positions 
  SET access_password = hash_password(access_password)
  WHERE access_password IS NOT NULL 
    AND access_password NOT LIKE '$2%'; -- Only hash if not already hashed
END;
$function$;