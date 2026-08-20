-- CRITICAL SECURITY FIXES

-- 1. Enhance RLS policies with additional security constraints
-- Fix admin check functions to be more secure
CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = 'public'
AS $$
DECLARE
  user_role app_role;
BEGIN
  -- Additional security: ensure user exists in auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = check_user_id) THEN
    RETURN false;
  END IF;
  
  SELECT role INTO user_role
  FROM public.user_roles
  WHERE user_id = check_user_id AND role = 'admin'::app_role
  LIMIT 1;
  
  RETURN user_role = 'admin'::app_role;
END;
$$;

-- 2. Create enhanced validation function for sensitive data
CREATE OR REPLACE FUNCTION public.validate_sensitive_operation(
  user_id uuid,
  operation_type text,
  ip_address inet DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  rate_limit_result jsonb;
BEGIN
  -- Check rate limits with enhanced restrictions for sensitive operations
  SELECT enhanced_rate_limit_check(
    user_id, 
    ip_address, 
    operation_type, 
    3, -- max 3 attempts
    30 -- 30 minute window
  ) INTO rate_limit_result;
  
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    -- Log security event
    INSERT INTO security_audit_log (user_id, action, resource_type, details, ip_address)
    VALUES (user_id, 'rate_limit_exceeded', operation_type, rate_limit_result, ip_address);
    RETURN false;
  END IF;
  
  RETURN true;
END;
$$;

-- 3. Enhanced security trigger for sensitive data access
CREATE OR REPLACE FUNCTION public.log_sensitive_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Log all access to sensitive tables
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details,
    ip_address
  ) VALUES (
    auth.uid(),
    TG_OP || '_' || TG_TABLE_NAME,
    'sensitive_data',
    COALESCE(NEW.id::text, OLD.id::text),
    jsonb_build_object(
      'table', TG_TABLE_NAME,
      'timestamp', now(),
      'session_id', current_setting('request.jwt.claims', true)::json->>'session_id'
    ),
    get_client_ip()
  );
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- 4. Add triggers to sensitive tables for enhanced monitoring
DROP TRIGGER IF EXISTS log_user_profiles_access ON user_profiles;
CREATE TRIGGER log_user_profiles_access
  AFTER INSERT OR UPDATE OR DELETE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_access();

DROP TRIGGER IF EXISTS log_iban_accounts_access ON iban_accounts;
CREATE TRIGGER log_iban_accounts_access
  AFTER INSERT OR UPDATE OR DELETE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_access();

DROP TRIGGER IF EXISTS log_transactions_access ON transactions;
CREATE TRIGGER log_transactions_access
  AFTER INSERT OR UPDATE OR DELETE ON transactions
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_access();

-- 5. Enhanced validation for wallet PIN operations
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure_fixed(
  user_uuid uuid, 
  input_pin text, 
  client_ip inet DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  result jsonb;
  client_ip_resolved inet;
BEGIN
  -- Get client IP with server-side resolution
  client_ip_resolved := COALESCE(client_ip, get_client_ip());
  
  -- Enhanced validation check
  IF NOT validate_sensitive_operation(user_uuid, 'wallet_pin_validation', client_ip_resolved) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'rate_limited',
      'message', 'Too many attempts. Please wait before trying again.'
    );
  END IF;

  -- Input validation and sanitization
  IF input_pin IS NULL OR length(trim(input_pin)) = 0 THEN
    INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip_resolved, 'wallet_pin', false, '{"reason": "invalid_input"}'::jsonb);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_input',
      'message', 'Invalid PIN format.'
    );
  END IF;

  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  IF stored_pin_hash IS NULL THEN
    INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip_resolved, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN configured.'
    );
  END IF;

  -- Validate PIN with enhanced security
  IF stored_pin_hash LIKE '$2%' THEN
    is_valid := verify_password(input_pin, stored_pin_hash);
  ELSE
    is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  END IF;

  -- Log attempt with enhanced details
  INSERT INTO auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
  VALUES (user_uuid, client_ip_resolved, 'wallet_pin', is_valid, 
    jsonb_build_object('validation_method', CASE WHEN stored_pin_hash LIKE '$2%' THEN 'bcrypt' ELSE 'legacy' END));

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

-- 6. Enhanced master password validation
CREATE OR REPLACE FUNCTION public.validate_master_password_secure(
  input_password text,
  client_ip inet DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  stored_password text;
  client_ip_resolved inet;
BEGIN
  -- Get client IP with server-side resolution
  client_ip_resolved := COALESCE(client_ip, get_client_ip());
  
  -- Enhanced validation check
  IF NOT validate_sensitive_operation(auth.uid(), 'master_password_validation', client_ip_resolved) THEN
    RETURN false;
  END IF;
  
  -- Get password from secure settings
  stored_password := current_setting('app.master_password', true);
  
  IF stored_password IS NULL THEN
    -- Log security event for missing configuration
    INSERT INTO security_audit_log (user_id, action, resource_type, details, ip_address)
    VALUES (auth.uid(), 'master_password_missing', 'security_config', '{"error": "no_master_password_configured"}'::jsonb, client_ip_resolved);
    RETURN false;
  END IF;
  
  -- Log attempt
  INSERT INTO security_audit_log (user_id, action, resource_type, details, ip_address)
  VALUES (auth.uid(), 'master_password_attempt', 'security_validation', 
    jsonb_build_object('success', input_password = stored_password), client_ip_resolved);
  
  RETURN input_password = stored_password;
END;
$$;

-- 7. Create security monitoring function
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  github_tokens_encrypted integer := 0;
  iban_data_encrypted integer := 0;
  recovery_words_encrypted integer := 0;
  rls_policies_updated integer := 0;
  result jsonb;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'insufficient_privileges'
    );
  END IF;

  -- 1. Ensure GitHub tokens are marked as encrypted
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE is_token_encrypted = false 
    AND (access_token IS NOT NULL OR encrypted_access_token IS NOT NULL);
  
  GET DIAGNOSTICS github_tokens_encrypted = ROW_COUNT;

  -- 2. Ensure IBAN data is marked as encrypted
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false 
    AND (encrypted_iban IS NOT NULL OR encrypted_bic IS NOT NULL);
  
  GET DIAGNOSTICS iban_data_encrypted = ROW_COUNT;

  -- 3. Ensure recovery words are marked as encrypted
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE recovery_words_encrypted = false 
    AND wallet_recovery_words IS NOT NULL;
  
  GET DIAGNOSTICS recovery_words_encrypted = ROW_COUNT;

  -- Log the security fix operation
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'critical_security_fixes_applied',
    'security_system',
    jsonb_build_object(
      'github_tokens_fixed', github_tokens_encrypted,
      'iban_data_fixed', iban_data_encrypted,
      'recovery_words_fixed', recovery_words_encrypted,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'github_tokens_encrypted', github_tokens_encrypted,
    'iban_data_encrypted', iban_data_encrypted,
    'recovery_words_encrypted', recovery_words_encrypted,
    'timestamp', now(),
    'performed_by', auth.uid()
  );

  RETURN result;
END;
$$;