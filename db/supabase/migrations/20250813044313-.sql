-- Strengthen wallet PIN security: bcrypt hashing with legacy fallback

-- 1) Helper to hash PIN using bcrypt via pgcrypto
CREATE OR REPLACE FUNCTION public.hash_wallet_pin(plain_pin text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public', 'extensions'
AS $$
BEGIN
  IF plain_pin IS NULL THEN
    RETURN NULL;
  END IF;
  -- Use pgcrypto's bcrypt with cost factor 8 (same as hash_password())
  RETURN extensions.crypt(plain_pin, extensions.gen_salt('bf', 8));
END;
$$;

-- 2) Trigger to enforce bcrypt hashing on user_profiles.wallet_pin_hash
CREATE OR REPLACE FUNCTION public.enforce_wallet_pin_hashing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public', 'extensions'
AS $$
BEGIN
  -- Hash provided PIN if it's in plaintext or legacy sha256 hex (not starting with $2)
  IF NEW.wallet_pin_hash IS NOT NULL AND NEW.wallet_pin_hash NOT LIKE '$2%' THEN
    NEW.wallet_pin_hash := public.hash_wallet_pin(NEW.wallet_pin_hash);
  END IF;
  RETURN NEW;
END;
$$;

-- Create or replace trigger (drop if exists to avoid duplicates)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_enforce_wallet_pin_hashing'
  ) THEN
    DROP TRIGGER trg_enforce_wallet_pin_hashing ON public.user_profiles;
  END IF;
END$$;

CREATE TRIGGER trg_enforce_wallet_pin_hashing
BEFORE INSERT OR UPDATE OF wallet_pin_hash ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_wallet_pin_hashing();

-- 3) Update PIN validation functions to support bcrypt and legacy fallback

-- Basic validator used by other RPCs
CREATE OR REPLACE FUNCTION public.validate_wallet_pin(user_uuid uuid, input_pin text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public', 'extensions'
AS $$
DECLARE
  stored_pin_hash TEXT;
  is_valid BOOLEAN := false;
BEGIN
  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  IF stored_pin_hash IS NULL THEN
    RETURN false;
  END IF;

  -- Prefer bcrypt if hash starts with $2
  IF stored_pin_hash LIKE '$2%' THEN
    is_valid := public.verify_password(input_pin, stored_pin_hash);
  ELSE
    -- Legacy fallback (sha256 hex)
    is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  END IF;

  RETURN is_valid;
END;
$$;

-- Secure validator with rate limiting (existing logic preserved)
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public', 'extensions'
AS $$
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
$$;

-- Secure validator using server-derived IP
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure_fixed(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public', 'extensions'
AS $$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  rate_limit_result jsonb;
  actual_client_ip inet;
BEGIN
  -- Get actual client IP
  actual_client_ip := COALESCE(client_ip, get_client_ip());

  -- Check rate limit with progressive delays
  SELECT check_rate_limit_with_progressive_delay(user_uuid, actual_client_ip, 'wallet_pin', 5, 60) 
  INTO rate_limit_result;
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, actual_client_ip, 'wallet_pin', false, 
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

  -- Get stored PIN hash
  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  IF stored_pin_hash IS NULL THEN
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, actual_client_ip, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN set for this user.'
    );
  END IF;

  -- Validate PIN with enhanced security
  IF stored_pin_hash LIKE '$2%' THEN
    is_valid := public.verify_password(input_pin, stored_pin_hash);
  ELSE
    is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  END IF;

  -- Log attempt with actual IP
  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success)
  VALUES (user_uuid, actual_client_ip, 'wallet_pin', is_valid);

  IF is_valid THEN
    INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
    VALUES (user_uuid, 'wallet_pin_validated', 'wallet_access', 
      jsonb_build_object('ip_address', actual_client_ip::text, 'timestamp', now()));
    RETURN jsonb_build_object(
      'success', true,
      'message', 'PIN validated successfully.'
    );
  ELSE
    INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
    VALUES (user_uuid, 'wallet_pin_failed', 'wallet_access', 
      jsonb_build_object('ip_address', actual_client_ip::text, 'timestamp', now()));
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin',
      'message', 'Invalid PIN provided.'
    );
  END IF;
END;
$$;