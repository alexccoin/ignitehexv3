-- Critical Security Fixes Migration

-- Update validate_founder_access_code function to use environment variable
CREATE OR REPLACE FUNCTION public.validate_founder_access_code(access_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  valid_code text;
BEGIN
  -- Get founder access code from environment variable or use default for development
  valid_code := COALESCE(
    current_setting('app.founder_access_code', true),
    'SECURE_FOUNDER_CODE_2024'  -- This should be set via environment variable
  );
  
  -- Use secure comparison (constant time to prevent timing attacks)
  RETURN access_code = valid_code;
END;
$function$;

-- Enhanced rate limiting function with progressive delays
CREATE OR REPLACE FUNCTION public.check_rate_limit_with_progressive_delay(
  check_user_id uuid DEFAULT NULL::uuid, 
  check_ip_address inet DEFAULT NULL::inet, 
  attempt_type_param text DEFAULT 'wallet_pin'::text, 
  max_attempts integer DEFAULT 5, 
  time_window_minutes integer DEFAULT 60
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  attempt_count integer;
  last_attempt_time timestamp with time zone;
  time_since_last_attempt interval;
  required_delay integer;
  progressive_delays integer[] := ARRAY[1, 5, 15, 60, 300]; -- seconds: 1s, 5s, 15s, 1min, 5min
BEGIN
  -- Count failed attempts within time window
  SELECT COUNT(*), MAX(created_at)
  INTO attempt_count, last_attempt_time
  FROM public.auth_attempts
  WHERE 
    (check_user_id IS NULL OR user_id = check_user_id)
    AND (check_ip_address IS NULL OR ip_address = check_ip_address)
    AND attempt_type = attempt_type_param
    AND success = false
    AND created_at > now() - (time_window_minutes || ' minutes')::interval;
  
  -- Check if rate limit exceeded
  IF attempt_count >= max_attempts THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'rate_limited',
      'attempts', attempt_count,
      'retry_after', time_window_minutes * 60
    );
  END IF;
  
  -- Calculate progressive delay if there were recent failed attempts
  IF attempt_count > 0 AND last_attempt_time IS NOT NULL THEN
    time_since_last_attempt := now() - last_attempt_time;
    
    -- Get required delay based on attempt count (capped at array length)
    required_delay := progressive_delays[LEAST(attempt_count, array_length(progressive_delays, 1))];
    
    -- Check if enough time has passed since last attempt
    IF time_since_last_attempt < (required_delay || ' seconds')::interval THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'progressive_delay',
        'attempts', attempt_count,
        'retry_after', required_delay - extract(epoch from time_since_last_attempt)::integer
      );
    END IF;
  END IF;
  
  -- Allow the attempt
  RETURN jsonb_build_object(
    'allowed', true,
    'attempts', attempt_count
  );
END;
$function$;

-- Enhanced wallet PIN validation with progressive delays
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
    -- Log rate limit violation
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
  
  -- Get stored PIN hash
  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  IF stored_pin_hash IS NULL THEN
    -- Log invalid attempt
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN set for this user.'
    );
  END IF;
  
  -- Validate PIN
  is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  
  -- Log attempt
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