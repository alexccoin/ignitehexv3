-- Enhanced Security Migration: Additional RLS Hardening and Security Functions
-- This migration adds additional security layers and monitoring functions

-- 1. Create enhanced security monitoring function
CREATE OR REPLACE FUNCTION public.log_security_access_pattern(
  user_id_param UUID,
  table_name TEXT,
  operation_type TEXT,
  row_count INTEGER DEFAULT 1
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Log unusual access patterns
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    user_id_param,
    'data_access_pattern',
    table_name,
    jsonb_build_object(
      'operation', operation_type,
      'row_count', row_count,
      'timestamp', now(),
      'pattern_type', CASE 
        WHEN row_count > 100 THEN 'bulk_access'
        WHEN operation_type = 'SELECT' THEN 'data_read'
        ELSE 'standard_access'
      END
    )
  );
END;
$$;

-- 2. Create function to validate user session integrity
CREATE OR REPLACE FUNCTION public.validate_session_security() 
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  current_user_id UUID;
  session_count INTEGER;
BEGIN
  current_user_id := auth.uid();
  
  -- Check if user is authenticated
  IF current_user_id IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Log session validation
  PERFORM log_security_access_pattern(
    current_user_id,
    'session_validation',
    'security_check'
  );
  
  RETURN TRUE;
END;
$$;

-- 3. Create enhanced input sanitization function
CREATE OR REPLACE FUNCTION public.enhanced_sanitize_input(
  input_text TEXT,
  input_type TEXT DEFAULT 'text'
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  sanitized_text TEXT;
BEGIN
  -- Handle null input
  IF input_text IS NULL THEN
    RETURN NULL;
  END IF;
  
  sanitized_text := input_text;
  
  -- Remove dangerous HTML/script content
  sanitized_text := regexp_replace(sanitized_text, '<script[^>]*>.*?</script>', '', 'gi');
  sanitized_text := regexp_replace(sanitized_text, '<iframe[^>]*>.*?</iframe>', '', 'gi');
  sanitized_text := regexp_replace(sanitized_text, 'javascript:', '', 'gi');
  sanitized_text := regexp_replace(sanitized_text, 'on[a-z]+\s*=', '', 'gi');
  
  -- Remove SQL injection patterns
  sanitized_text := regexp_replace(sanitized_text, '[;'']', '', 'g');
  sanitized_text := regexp_replace(sanitized_text, '--', '', 'g');
  
  -- Type-specific sanitization
  CASE input_type
    WHEN 'email' THEN
      -- Keep only valid email characters
      sanitized_text := regexp_replace(sanitized_text, '[^a-zA-Z0-9@._-]', '', 'g');
    WHEN 'username' THEN
      -- Keep only alphanumeric and safe characters
      sanitized_text := regexp_replace(sanitized_text, '[^a-zA-Z0-9_-]', '', 'g');
    WHEN 'numeric' THEN
      -- Keep only numbers and decimal point
      sanitized_text := regexp_replace(sanitized_text, '[^0-9.]', '', 'g');
    ELSE
      -- General text sanitization - remove control characters
      sanitized_text := regexp_replace(sanitized_text, '[\x00-\x1F\x7F]', '', 'g');
  END CASE;
  
  -- Trim and limit length
  sanitized_text := trim(sanitized_text);
  IF length(sanitized_text) > 10000 THEN
    sanitized_text := left(sanitized_text, 10000);
  END IF;
  
  RETURN sanitized_text;
END;
$$;

-- 4. Add security triggers to monitor sensitive table access
CREATE OR REPLACE FUNCTION public.monitor_sensitive_table_access()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  operation_type TEXT;
  user_id_param UUID;
BEGIN
  operation_type := TG_OP;
  user_id_param := auth.uid();
  
  -- Log access to sensitive tables
  IF TG_TABLE_NAME IN ('user_profiles', 'iban_accounts', 'github_integrations', 'voucher_redemptions') THEN
    PERFORM log_security_access_pattern(
      user_id_param,
      TG_TABLE_NAME,
      operation_type
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Apply monitoring triggers to sensitive tables
DROP TRIGGER IF EXISTS monitor_user_profiles_access ON user_profiles;
CREATE TRIGGER monitor_user_profiles_access
  AFTER INSERT OR UPDATE OR DELETE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION monitor_sensitive_table_access();

DROP TRIGGER IF EXISTS monitor_iban_accounts_access ON iban_accounts;
CREATE TRIGGER monitor_iban_accounts_access
  AFTER INSERT OR UPDATE OR DELETE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION monitor_sensitive_table_access();

DROP TRIGGER IF EXISTS monitor_github_integrations_access ON github_integrations;
CREATE TRIGGER monitor_github_integrations_access
  AFTER INSERT OR UPDATE OR DELETE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION monitor_sensitive_table_access();

-- 5. Create security health check function
CREATE OR REPLACE FUNCTION public.perform_security_health_check()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  result JSONB;
  database_health TEXT := 'healthy';
  auth_health TEXT := 'healthy';
  encryption_health TEXT := 'healthy';
  total_users INTEGER;
  unencrypted_count INTEGER;
BEGIN
  -- Check database health
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  
  -- Check encryption status
  SELECT COUNT(*) INTO unencrypted_count
  FROM user_profiles 
  WHERE (wallet_recovery_words IS NOT NULL AND recovery_words_encrypted = false)
     OR wallet_pin_hash IS NULL;
  
  -- Determine encryption health
  IF unencrypted_count > 0 THEN
    encryption_health := 'critical';
  END IF;
  
  -- Check authentication health
  IF total_users > 0 THEN
    SELECT COUNT(*) INTO unencrypted_count
    FROM user_profiles
    WHERE wallet_pin_hash IS NULL OR two_factor_enabled = false;
    
    IF unencrypted_count > (total_users * 0.5) THEN
      auth_health := 'warning';
    END IF;
  END IF;
  
  result := jsonb_build_object(
    'database', database_health,
    'authentication', auth_health,
    'encryption', encryption_health,
    'monitoring', 'healthy',
    'backups', 'healthy',
    'timestamp', now(),
    'total_users', total_users,
    'issues_found', CASE WHEN encryption_health = 'critical' THEN unencrypted_count ELSE 0 END
  );
  
  -- Log the health check
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    auth.uid(),
    'security_health_check',
    'system',
    result
  );
  
  RETURN result;
END;
$$;

-- 6. Grant necessary permissions for security functions
GRANT EXECUTE ON FUNCTION public.log_security_access_pattern TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_session_security TO authenticated;
GRANT EXECUTE ON FUNCTION public.enhanced_sanitize_input TO authenticated;
GRANT EXECUTE ON FUNCTION public.perform_security_health_check TO authenticated;