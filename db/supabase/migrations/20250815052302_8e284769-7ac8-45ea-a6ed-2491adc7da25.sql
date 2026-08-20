-- Fix security linter warnings: Set search_path for security functions
-- This prevents SQL injection through function definitions

-- Fix validate_github_token_security function
CREATE OR REPLACE FUNCTION validate_github_token_security()
RETURNS TRIGGER AS $$
BEGIN
  -- Prevent storing plaintext tokens
  IF NEW.access_token IS NOT NULL THEN
    RAISE EXCEPTION 'Plaintext GitHub access_token is not allowed. Use encrypted_access_token with is_token_encrypted=true.';
  END IF;
  
  -- Ensure encrypted tokens are properly marked
  IF (NEW.encrypted_access_token IS NULL) OR (COALESCE(NEW.is_token_encrypted, false) = false) THEN
    RAISE EXCEPTION 'Encrypted token and is_token_encrypted=true are required.';
  END IF;
  
  -- Validate GitHub username format for security
  IF NEW.github_username IS NOT NULL AND (
    length(NEW.github_username) > 39 OR 
    NEW.github_username ~ '[^a-zA-Z0-9\-]'
  ) THEN
    RAISE EXCEPTION 'Invalid GitHub username format';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- Fix validate_and_sanitize_input function
CREATE OR REPLACE FUNCTION validate_and_sanitize_input(input_text text, max_length integer DEFAULT 1000)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public'
AS $$
BEGIN
  -- Handle null input
  IF input_text IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Advanced XSS protection
  input_text := regexp_replace(input_text, '<script[^>]*>.*?</script>', '', 'gi');
  input_text := regexp_replace(input_text, '<iframe[^>]*>.*?</iframe>', '', 'gi');
  input_text := regexp_replace(input_text, 'javascript:', '', 'gi');
  input_text := regexp_replace(input_text, 'data:', '', 'gi');
  input_text := regexp_replace(input_text, 'on[a-z]+\s*=', '', 'gi');
  input_text := regexp_replace(input_text, '&lt;script', '', 'gi');
  
  -- SQL injection protection
  input_text := replace(input_text, '''', '');
  input_text := replace(input_text, ';', '');
  input_text := replace(input_text, '--', '');
  
  -- Length validation
  IF length(input_text) > max_length THEN
    input_text := left(input_text, max_length);
  END IF;
  
  RETURN trim(input_text);
END;
$$;

-- Fix enhanced_rate_limit_check function  
CREATE OR REPLACE FUNCTION enhanced_rate_limit_check(
  check_user_id uuid DEFAULT NULL,
  check_ip_address inet DEFAULT NULL,
  operation_type text DEFAULT 'general',
  max_attempts integer DEFAULT 3,
  time_window_minutes integer DEFAULT 15
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  attempt_count integer;
  last_attempt_time timestamp with time zone;
  progressive_delays integer[] := ARRAY[5, 15, 60, 300, 900]; -- 5s, 15s, 1min, 5min, 15min
  required_delay integer;
BEGIN
  -- Count recent failed attempts
  SELECT COUNT(*), MAX(created_at)
  INTO attempt_count, last_attempt_time
  FROM public.auth_attempts
  WHERE 
    (check_user_id IS NULL OR user_id = check_user_id)
    AND (check_ip_address IS NULL OR ip_address = check_ip_address)
    AND attempt_type = operation_type
    AND success = false
    AND created_at > now() - (time_window_minutes || ' minutes')::interval;
  
  -- Check rate limit
  IF attempt_count >= max_attempts THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'rate_limited',
      'attempts', attempt_count,
      'retry_after', time_window_minutes * 60
    );
  END IF;
  
  -- Progressive delay enforcement
  IF attempt_count > 0 AND last_attempt_time IS NOT NULL THEN
    required_delay := progressive_delays[LEAST(attempt_count, array_length(progressive_delays, 1))];
    
    IF (now() - last_attempt_time) < (required_delay || ' seconds')::interval THEN
      RETURN jsonb_build_object(
        'allowed', false,
        'reason', 'progressive_delay',
        'attempts', attempt_count,
        'retry_after', required_delay - extract(epoch from (now() - last_attempt_time))::integer
      );
    END IF;
  END IF;
  
  RETURN jsonb_build_object('allowed', true, 'attempts', attempt_count);
END;
$$;

-- Add comprehensive security monitoring for sensitive data access
CREATE OR REPLACE FUNCTION audit_sensitive_data_access()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER SET search_path = 'public'
AS $$
BEGIN
  -- Log access to sensitive financial data
  IF TG_TABLE_NAME IN ('iban_accounts', 'prepaid_cards', 'transactions', 'user_profiles') THEN
    INSERT INTO public.security_audit_log (
      user_id,
      action,
      resource_type,
      resource_id,
      details,
      ip_address
    ) VALUES (
      auth.uid(),
      'sensitive_data_' || TG_OP,
      TG_TABLE_NAME,
      COALESCE(NEW.id, OLD.id)::text,
      jsonb_build_object(
        'operation', TG_OP,
        'table', TG_TABLE_NAME,
        'timestamp', now()
      ),
      get_client_ip()
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Apply audit triggers to sensitive tables (INSERT, UPDATE, DELETE only - not SELECT as it causes too much noise)
DROP TRIGGER IF EXISTS audit_iban_access ON public.iban_accounts;
CREATE TRIGGER audit_iban_access
  AFTER INSERT OR UPDATE OR DELETE ON public.iban_accounts
  FOR EACH ROW
  EXECUTE FUNCTION audit_sensitive_data_access();

DROP TRIGGER IF EXISTS audit_prepaid_cards_access ON public.prepaid_cards;
CREATE TRIGGER audit_prepaid_cards_access
  AFTER INSERT OR UPDATE OR DELETE ON public.prepaid_cards
  FOR EACH ROW
  EXECUTE FUNCTION audit_sensitive_data_access();

DROP TRIGGER IF EXISTS audit_transactions_access ON public.transactions;
CREATE TRIGGER audit_transactions_access
  AFTER INSERT OR UPDATE OR DELETE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION audit_sensitive_data_access();

-- Create security metrics function for monitoring
CREATE OR REPLACE FUNCTION get_security_metrics(time_period_hours integer DEFAULT 24)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  failed_attempts integer;
  sensitive_data_accesses integer;
  admin_actions integer;
  result jsonb;
BEGIN
  -- Count failed authentication attempts in time period
  SELECT COUNT(*) INTO failed_attempts
  FROM public.auth_attempts
  WHERE success = false
    AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  -- Count sensitive data access events
  SELECT COUNT(*) INTO sensitive_data_accesses
  FROM public.security_audit_log
  WHERE action LIKE 'sensitive_data_%'
    AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  -- Count admin actions
  SELECT COUNT(*) INTO admin_actions
  FROM public.security_audit_log
  WHERE action LIKE 'admin_%'
    AND created_at > now() - (time_period_hours || ' hours')::interval;
  
  result := jsonb_build_object(
    'time_period_hours', time_period_hours,
    'failed_attempts', failed_attempts,
    'sensitive_data_accesses', sensitive_data_accesses,
    'admin_actions', admin_actions,
    'generated_at', now()
  );
  
  RETURN result;
END;
$$;