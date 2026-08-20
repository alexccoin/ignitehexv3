-- Security Fix 1: Fix RLS violations in arss_transactions table
-- The current policy seems to have issues, let's ensure proper user isolation

-- First, let's update the RLS policy to be more explicit about user ownership
DROP POLICY IF EXISTS "Users can create transactions" ON public.arss_transactions;
DROP POLICY IF EXISTS "Users can view their own transactions" ON public.arss_transactions;

-- Create stronger RLS policies for arss_transactions
CREATE POLICY "Users can create their own transactions" 
ON public.arss_transactions 
FOR INSERT 
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Users can view only their own transactions" 
ON public.arss_transactions 
FOR SELECT 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL);

-- Admin override policy for transactions
CREATE POLICY "Admins can view all transactions" 
ON public.arss_transactions 
FOR SELECT 
USING (is_admin(auth.uid()));

-- Security Fix 2: Strengthen GitHub integrations security
-- Add trigger to ensure no plaintext tokens are stored
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply the trigger to enforce security
DROP TRIGGER IF EXISTS enforce_github_token_security ON public.github_integrations;
CREATE TRIGGER enforce_github_token_security
  BEFORE INSERT OR UPDATE ON public.github_integrations
  FOR EACH ROW
  EXECUTE FUNCTION validate_github_token_security();

-- Security Fix 3: Enhance chat message security
-- Update chat message policy to be more restrictive
DROP POLICY IF EXISTS "authenticated_can_read_public_chat" ON public.chat_messages;

-- Create more secure chat policies
CREATE POLICY "Users can read public chat when authenticated and not banned" 
ON public.chat_messages 
FOR SELECT 
USING (
  auth.uid() IS NOT NULL 
  AND room_type = 'public'
  AND NOT EXISTS (
    SELECT 1 FROM public.chat_bans b
    WHERE b.user_id = auth.uid()
      AND (b.room_type = 'public' OR b.room_type = 'all')
      AND (b.expires_at IS NULL OR b.expires_at > now())
  )
);

-- Security Fix 4: Add comprehensive security event logging
CREATE OR REPLACE FUNCTION log_security_violation(
  violation_type text,
  resource_table text,
  user_id_param uuid DEFAULT NULL,
  details_param jsonb DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    COALESCE(user_id_param, auth.uid()),
    violation_type,
    resource_table,
    COALESCE(details_param, '{}'),
    get_client_ip()
  );
END;
$$;

-- Add security monitoring trigger for sensitive data access
CREATE OR REPLACE FUNCTION audit_sensitive_data_access()
RETURNS TRIGGER AS $$
BEGIN
  -- Log access to sensitive financial data
  IF TG_TABLE_NAME IN ('iban_accounts', 'prepaid_cards', 'transactions', 'user_profiles') THEN
    PERFORM log_security_violation(
      'sensitive_data_access',
      TG_TABLE_NAME,
      auth.uid(),
      jsonb_build_object(
        'operation', TG_OP,
        'table', TG_TABLE_NAME,
        'record_id', COALESCE(NEW.id, OLD.id),
        'timestamp', now()
      )
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply audit triggers to sensitive tables
CREATE TRIGGER audit_iban_access
  AFTER SELECT OR INSERT OR UPDATE OR DELETE ON public.iban_accounts
  FOR EACH ROW
  EXECUTE FUNCTION audit_sensitive_data_access();

CREATE TRIGGER audit_prepaid_cards_access
  AFTER SELECT OR INSERT OR UPDATE OR DELETE ON public.prepaid_cards
  FOR EACH ROW
  EXECUTE FUNCTION audit_sensitive_data_access();

-- Security Fix 5: Enhanced input validation function
CREATE OR REPLACE FUNCTION validate_and_sanitize_input(input_text text, max_length integer DEFAULT 1000)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Security Fix 6: Rate limiting enhancement for sensitive operations
CREATE OR REPLACE FUNCTION enhanced_rate_limit_check(
  check_user_id uuid DEFAULT NULL,
  check_ip_address inet DEFAULT NULL,
  operation_type text DEFAULT 'general',
  max_attempts integer DEFAULT 3,
  time_window_minutes integer DEFAULT 15
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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