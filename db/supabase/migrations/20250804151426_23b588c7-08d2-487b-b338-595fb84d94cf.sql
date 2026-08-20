-- Create edge function for secure master password validation
CREATE OR REPLACE FUNCTION public.validate_master_password_secure(input_password text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  valid_password text;
  rate_limit_result jsonb;
BEGIN
  -- Check rate limit with progressive delays for master password attempts
  SELECT check_rate_limit_with_progressive_delay(
    NULL, -- No specific user for master password
    client_ip, 
    'master_password', 
    3, -- Only 3 attempts per hour
    60
  ) INTO rate_limit_result;
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    -- Log rate limit violation
    INSERT INTO public.auth_attempts (ip_address, attempt_type, success, additional_data)
    VALUES (client_ip, 'master_password', false, rate_limit_result);
    
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
  
  -- Get master password from environment variable
  valid_password := COALESCE(
    current_setting('app.master_password', true),
    'SECURE_MASTER_PASSWORD_2024'  -- This should be set via environment variable
  );
  
  -- Validate password
  IF input_password = valid_password THEN
    -- Log successful attempt
    INSERT INTO public.auth_attempts (ip_address, attempt_type, success)
    VALUES (client_ip, 'master_password', true);
    
    INSERT INTO public.security_audit_log (action, resource_type, details)
    VALUES ('master_password_validated', 'system_access', 
      jsonb_build_object('ip_address', client_ip::text, 'timestamp', now()));
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Master password validated successfully.'
    );
  ELSE
    -- Log failed attempt
    INSERT INTO public.auth_attempts (ip_address, attempt_type, success)
    VALUES (client_ip, 'master_password', false);
    
    INSERT INTO public.security_audit_log (action, resource_type, details)
    VALUES ('master_password_failed', 'system_access', 
      jsonb_build_object('ip_address', client_ip::text, 'timestamp', now()));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_password',
      'message', 'Invalid master password.'
    );
  END IF;
END;
$function$;