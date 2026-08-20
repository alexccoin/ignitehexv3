-- Enable pgcrypto extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Drop existing functions to recreate with correct schema references
DROP FUNCTION IF EXISTS public.verify_pin_secure(text, text);
DROP FUNCTION IF EXISTS public.hash_pin_secure(text, uuid);

-- Recreate verify_pin_secure with correct digest schema
CREATE FUNCTION public.verify_pin_secure(pin_text text, stored_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
  
  calculated_hash := encode(extensions.digest(pin_text || salt || iterations::text, 'sha256'), 'hex');
  
  RETURN calculated_hash = stored_hash_value;
END;
$$;

-- Recreate hash_pin_secure with correct digest schema
CREATE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  salt text;
  hash_input text;
  iterations int := 10000;
BEGIN
  salt := encode(extensions.digest(user_uuid::text || extract(epoch from now())::text || random()::text, 'sha256'), 'hex');
  hash_input := pin_text || salt || iterations::text;
  RETURN iterations::text || '$' || salt || '$' || encode(extensions.digest(hash_input, 'sha256'), 'hex');
END;
$$;

-- Update validate_wallet_pin_secure to use correct digest schema
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  rate_limit_result jsonb;
BEGIN
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
        WHEN rate_limit_result->>'reason' = 'rate_limited' THEN 'Too many failed attempts.'
        WHEN rate_limit_result->>'reason' = 'progressive_delay' THEN 'Please wait ' || (rate_limit_result->>'retry_after') || ' seconds.'
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

  IF stored_pin_hash LIKE '$2%' THEN
    is_valid := public.verify_password(input_pin, stored_pin_hash);
  ELSIF stored_pin_hash LIKE '%$%$%' THEN
    is_valid := verify_pin_secure(input_pin, stored_pin_hash);
  ELSE
    is_valid := stored_pin_hash = encode(extensions.digest(input_pin, 'sha256'), 'hex');
  END IF;

  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success)
  VALUES (user_uuid, client_ip, 'wallet_pin', is_valid);

  IF is_valid THEN
    RETURN jsonb_build_object('success', true, 'message', 'PIN validated successfully.');
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'invalid_pin', 'message', 'Invalid PIN provided.');
  END IF;
END;
$$;