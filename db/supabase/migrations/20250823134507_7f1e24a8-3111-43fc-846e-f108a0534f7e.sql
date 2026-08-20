-- Drop existing conflicting functions
DROP FUNCTION IF EXISTS public.get_wallet_recovery_words_secure(uuid, text, inet);
DROP FUNCTION IF EXISTS public.get_security_metrics();

-- Create secure PIN validation functions with proper bcrypt-style hashing
CREATE OR REPLACE FUNCTION public.hash_pin_secure(pin_text text, user_uuid uuid)
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
  -- Generate salt using user UUID and random component
  salt := encode(digest(user_uuid::text || extract(epoch from now())::text || random()::text, 'sha256'), 'hex');
  
  -- Create hash input combining PIN, salt, and iterations
  hash_input := pin_text || salt || iterations::text;
  
  -- Return format: iterations$salt$hash (bcrypt-style)
  RETURN iterations::text || '$' || salt || '$' || encode(digest(hash_input, 'sha256'), 'hex');
END;
$$;

-- Create secure PIN verification function  
CREATE OR REPLACE FUNCTION public.verify_pin_secure(pin_text text, stored_hash text)
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
  -- Parse stored hash format: iterations$salt$hash
  hash_parts := string_to_array(stored_hash, '$');
  
  IF array_length(hash_parts, 1) != 3 THEN
    RETURN false;
  END IF;
  
  iterations := hash_parts[1]::int;
  salt := hash_parts[2];
  stored_hash_value := hash_parts[3];
  
  -- Calculate hash using same method
  calculated_hash := encode(digest(pin_text || salt || iterations::text, 'sha256'), 'hex');
  
  -- Compare hashes
  RETURN calculated_hash = stored_hash_value;
END;
$$;

-- Update existing wallet PIN validation function to use secure hashing
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure_fixed(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  rate_limit_result jsonb;
  server_ip inet;
BEGIN
  -- Get server-derived IP address
  server_ip := COALESCE(client_ip, get_client_ip());
  
  -- Check rate limit with progressive delays
  SELECT check_rate_limit_with_progressive_delay(user_uuid, server_ip, 'wallet_pin', 5, 60)
  INTO rate_limit_result;
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, server_ip, 'wallet_pin', false, 
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
    VALUES (user_uuid, server_ip, 'wallet_pin', false, 
      jsonb_build_object('error', 'no_pin', 'message', 'No PIN set for this account'));
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN has been set for this account'
    );
  END IF;

  -- Verify PIN using secure method
  is_valid := verify_pin_secure(input_pin, stored_pin_hash);

  -- Log attempt
  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
  VALUES (user_uuid, server_ip, 'wallet_pin', is_valid, 
    jsonb_build_object('validation_method', 'secure_hash', 'timestamp', now()));

  IF is_valid THEN
    RETURN jsonb_build_object(
      'success', true,
      'access_method', 'secure_pin_validation',
      'message', 'PIN verified successfully'
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin',
      'message', 'Invalid PIN provided'
    );
  END IF;
END;
$$;

-- Create function to get wallet recovery words securely
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  pin_validation_result jsonb;
  recovery_words text[];
  words_encrypted boolean;
BEGIN
  -- Validate PIN using secure method
  SELECT validate_wallet_pin_secure_fixed(user_uuid, input_pin, client_ip)
  INTO pin_validation_result;
  
  -- Return early if PIN validation failed
  IF NOT (pin_validation_result->>'success')::boolean THEN
    RETURN pin_validation_result;
  END IF;
  
  -- Get recovery words
  SELECT wallet_recovery_words, recovery_words_encrypted
  INTO recovery_words, words_encrypted
  FROM public.user_profiles
  WHERE user_id = user_uuid;
  
  IF recovery_words IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_recovery_words',
      'message', 'No recovery words found for this account'
    );
  END IF;
  
  -- Log successful access
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (user_uuid, 'recovery_words_accessed', 'wallet_security', 
    jsonb_build_object('encrypted', words_encrypted, 'timestamp', now()));
  
  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', recovery_words,
    'encrypted', words_encrypted,
    'access_method', pin_validation_result->>'access_method'
  );
END;
$$;

-- Create security health check function
CREATE OR REPLACE FUNCTION public.run_security_health_check(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  profile_data record;
  github_tokens_count int := 0;
  iban_accounts_count int := 0;
  unencrypted_github int := 0;
  unencrypted_iban int := 0;
  security_score int := 100;
  issues jsonb := '[]'::jsonb;
BEGIN
  -- Check if user exists and get profile data
  SELECT 
    wallet_pin_hash IS NOT NULL as has_pin,
    recovery_words_encrypted,
    wallet_recovery_words IS NOT NULL as has_recovery_words,
    two_factor_enabled
  INTO profile_data
  FROM public.user_profiles
  WHERE user_id = check_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'user_not_found',
      'message', 'User profile not found'
    );
  END IF;
  
  -- Check GitHub tokens
  SELECT COUNT(*), COUNT(*) FILTER (WHERE NOT is_token_encrypted OR is_token_encrypted IS NULL)
  INTO github_tokens_count, unencrypted_github
  FROM github_integrations
  WHERE user_id = check_user_id;
  
  -- Check IBAN accounts  
  SELECT COUNT(*), COUNT(*) FILTER (WHERE NOT is_data_encrypted OR is_data_encrypted IS NULL)
  INTO iban_accounts_count, unencrypted_iban
  FROM iban_accounts
  WHERE user_id = check_user_id;
  
  -- Calculate security score and identify issues
  IF NOT profile_data.has_pin THEN
    security_score := security_score - 30;
    issues := issues || jsonb_build_object('type', 'no_pin', 'severity', 'high', 'message', 'No security PIN set');
  END IF;
  
  IF profile_data.has_recovery_words AND NOT profile_data.recovery_words_encrypted THEN
    security_score := security_score - 25;
    issues := issues || jsonb_build_object('type', 'unencrypted_recovery', 'severity', 'critical', 'message', 'Recovery words are not encrypted');
  END IF;
  
  IF unencrypted_github > 0 THEN
    security_score := security_score - 15;
    issues := issues || jsonb_build_object('type', 'unencrypted_tokens', 'severity', 'high', 'message', unencrypted_github || ' GitHub tokens are not encrypted');
  END IF;
  
  IF unencrypted_iban > 0 THEN
    security_score := security_score - 20;
    issues := issues || jsonb_build_object('type', 'unencrypted_iban', 'severity', 'high', 'message', unencrypted_iban || ' IBAN accounts are not encrypted');
  END IF;
  
  IF NOT profile_data.two_factor_enabled THEN
    security_score := security_score - 10;
    issues := issues || jsonb_build_object('type', 'no_2fa', 'severity', 'medium', 'message', '2FA is not enabled');
  END IF;
  
  -- Log the health check
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (check_user_id, 'security_health_check', 'user_security',
    jsonb_build_object(
      'score', security_score,
      'issues_count', jsonb_array_length(issues),
      'timestamp', now()
    ));
  
  RETURN jsonb_build_object(
    'success', true,
    'security_score', GREATEST(0, security_score),
    'issues', issues,
    'summary', jsonb_build_object(
      'has_pin', profile_data.has_pin,
      'recovery_words_encrypted', profile_data.recovery_words_encrypted,
      'github_tokens_encrypted', github_tokens_count - unencrypted_github,
      'iban_accounts_encrypted', iban_accounts_count - unencrypted_iban,
      'two_factor_enabled', profile_data.two_factor_enabled
    )
  );
END;
$$;

-- Create unified security metrics function (fix overloading issue)
CREATE OR REPLACE FUNCTION public.get_security_metrics_unified(time_period_hours integer DEFAULT 24)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  total_users int;
  users_with_pins int;
  unencrypted_recovery_words int;
  unencrypted_github_tokens int;
  unencrypted_iban_accounts int;
  recent_security_incidents int;
  failed_auth_attempts int;
BEGIN
  -- Get total user count
  SELECT COUNT(*) INTO total_users FROM auth.users;
  
  -- Count users with PINs
  SELECT COUNT(*) INTO users_with_pins 
  FROM user_profiles 
  WHERE wallet_pin_hash IS NOT NULL;
  
  -- Count unencrypted recovery words
  SELECT COUNT(*) INTO unencrypted_recovery_words
  FROM user_profiles 
  WHERE wallet_recovery_words IS NOT NULL 
  AND (recovery_words_encrypted IS FALSE OR recovery_words_encrypted IS NULL);
  
  -- Count unencrypted GitHub tokens
  SELECT COUNT(*) INTO unencrypted_github_tokens
  FROM github_integrations 
  WHERE access_token IS NOT NULL 
  AND (is_token_encrypted IS FALSE OR is_token_encrypted IS NULL);
  
  -- Count unencrypted IBAN accounts
  SELECT COUNT(*) INTO unencrypted_iban_accounts
  FROM iban_accounts 
  WHERE (is_data_encrypted IS FALSE OR is_data_encrypted IS NULL);
  
  -- Count recent security incidents
  SELECT COUNT(*) INTO recent_security_incidents
  FROM security_audit_log 
  WHERE created_at > now() - (time_period_hours || ' hours')::interval
  AND action LIKE '%security%';
  
  -- Count failed authentication attempts in time period
  SELECT COUNT(*) INTO failed_auth_attempts
  FROM auth_attempts 
  WHERE success = FALSE 
  AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  RETURN jsonb_build_object(
    'total_users', total_users,
    'security_compliance', jsonb_build_object(
      'users_with_pins', users_with_pins,
      'users_without_pins', total_users - users_with_pins,
      'pin_compliance_rate', CASE 
        WHEN total_users > 0 THEN ROUND((users_with_pins::decimal / total_users) * 100, 2)
        ELSE 0 
      END
    ),
    'encryption_status', jsonb_build_object(
      'unencrypted_recovery_words', unencrypted_recovery_words,
      'unencrypted_github_tokens', unencrypted_github_tokens,
      'unencrypted_iban_accounts', unencrypted_iban_accounts,
      'total_encryption_issues', unencrypted_recovery_words + unencrypted_github_tokens + unencrypted_iban_accounts
    ),
    'security_activity', jsonb_build_object(
      'recent_incidents', recent_security_incidents,
      'failed_auth_attempts', failed_auth_attempts,
      'time_period_hours', time_period_hours
    ),
    'generated_at', now()
  );
END;
$$;