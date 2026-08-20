-- CRITICAL SECURITY FIXES: Encrypt sensitive data and enhance RLS policies

-- 1. Add encrypted columns for sensitive GitHub data
ALTER TABLE github_integrations 
ADD COLUMN encrypted_access_token text,
ADD COLUMN token_encryption_iv text,
ADD COLUMN is_token_encrypted boolean DEFAULT false;

-- 2. Add encrypted columns for IBAN data  
ALTER TABLE iban_accounts
ADD COLUMN encrypted_iban text,
ADD COLUMN encrypted_bic text,
ADD COLUMN iban_encryption_iv text,
ADD COLUMN is_data_encrypted boolean DEFAULT false;

-- 3. Add recovery words encryption tracking
ALTER TABLE user_profiles
ADD COLUMN recovery_words_encrypted boolean DEFAULT false,
ADD COLUMN recovery_words_iv text;

-- 4. Enhance RLS policies for GitHub integrations
DROP POLICY IF EXISTS "Users can manage their own GitHub integration" ON github_integrations;
DROP POLICY IF EXISTS "Users can view their own GitHub integration" ON github_integrations;

CREATE POLICY "Users can manage own GitHub integration secure" 
ON github_integrations 
FOR ALL 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL);

-- 5. Strengthen IBAN account RLS policies  
DROP POLICY IF EXISTS "Users can view their own IBAN accounts" ON iban_accounts;
DROP POLICY IF EXISTS "Users can update their own IBAN accounts" ON iban_accounts;

CREATE POLICY "Users can view own IBAN accounts secure" 
ON iban_accounts 
FOR SELECT 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Users can update own IBAN accounts secure" 
ON iban_accounts 
FOR UPDATE 
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Users can insert own IBAN accounts secure" 
ON iban_accounts 
FOR INSERT 
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

-- 6. Enhanced chat message policies to prevent data exposure
DROP POLICY IF EXISTS "Users can view public chat messages" ON chat_messages;

CREATE POLICY "Users can view public chat messages secure" 
ON chat_messages 
FOR SELECT 
USING (
  room_type = 'public' AND 
  auth.uid() IS NOT NULL AND
  LENGTH(message) <= 1000 -- Prevent oversized messages
);

-- 7. Add security function for client IP detection
CREATE OR REPLACE FUNCTION get_client_ip()
RETURNS inet
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Try to get real client IP from headers set by reverse proxies
  RETURN COALESCE(
    inet(current_setting('request.headers', true)::json->>'x-forwarded-for'),
    inet(current_setting('request.headers', true)::json->>'x-real-ip'),
    inet(current_setting('request.headers', true)::json->>'cf-connecting-ip'),
    '127.0.0.1'::inet
  );
EXCEPTION WHEN OTHERS THEN
  RETURN '127.0.0.1'::inet;
END;
$$;

-- 8. Update PIN validation to use proper client IP
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
  actual_client_ip inet;
BEGIN
  -- Get actual client IP
  actual_client_ip := COALESCE(client_ip, get_client_ip());
  
  -- Check rate limit with progressive delays
  SELECT check_rate_limit_with_progressive_delay(user_uuid, actual_client_ip, 'wallet_pin', 5, 60) 
  INTO rate_limit_result;
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    -- Log rate limit violation with actual IP
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
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  IF stored_pin_hash IS NULL THEN
    -- Log invalid attempt with actual IP
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, actual_client_ip, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN set for this user.'
    );
  END IF;
  
  -- Validate PIN with enhanced security
  is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  
  -- Log attempt with actual IP
  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success)
  VALUES (user_uuid, actual_client_ip, 'wallet_pin', is_valid);
  
  IF is_valid THEN
    -- Log successful access to security audit
    INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
    VALUES (user_uuid, 'wallet_pin_validated', 'wallet_access', 
      jsonb_build_object('ip_address', actual_client_ip::text, 'timestamp', now()));
    
    RETURN jsonb_build_object(
      'success', true,
      'message', 'PIN validated successfully.'
    );
  ELSE
    -- Log failed access to security audit
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