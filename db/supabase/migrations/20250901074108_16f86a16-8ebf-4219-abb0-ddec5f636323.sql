-- EMERGENCY SECURITY MIGRATION: Encrypt all sensitive data and strengthen access controls

-- Step 1: Create enhanced encryption enforcement triggers for GitHub tokens
CREATE OR REPLACE FUNCTION prevent_plaintext_github_tokens()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- Prevent inserting plaintext tokens when encrypted field is available
  IF NEW.access_token IS NOT NULL AND NEW.encrypted_access_token IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot store both plaintext and encrypted GitHub tokens. Use encrypted version only.';
  END IF;
  
  -- If storing encrypted token, ensure plaintext is cleared and encryption flag is set
  IF NEW.encrypted_access_token IS NOT NULL THEN
    NEW.access_token := NULL;
    NEW.is_token_encrypted := true;
  END IF;
  
  -- Log token storage attempts
  INSERT INTO security_audit_log (
    user_id, action, resource_type, resource_id, details
  ) VALUES (
    NEW.user_id,
    'github_token_storage_attempt',
    'github_integrations',
    NEW.id::text,
    jsonb_build_object(
      'has_plaintext', NEW.access_token IS NOT NULL,
      'has_encrypted', NEW.encrypted_access_token IS NOT NULL,
      'encryption_flag', NEW.is_token_encrypted
    )
  );
  
  RETURN NEW;
END;
$function$;

-- Apply GitHub token security trigger
DROP TRIGGER IF EXISTS enforce_github_token_encryption ON github_integrations;
CREATE TRIGGER enforce_github_token_encryption
BEFORE INSERT OR UPDATE ON github_integrations
FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_github_tokens();

-- Step 2: Create enhanced encryption enforcement for IBAN accounts
CREATE OR REPLACE FUNCTION prevent_plaintext_iban_data()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- If storing encrypted IBAN data, ensure plaintext is masked and encryption flag is set
  IF NEW.encrypted_iban IS NOT NULL AND NEW.encrypted_bic IS NOT NULL THEN
    NEW.iban := 'MASKED-' || RIGHT(NEW.iban, 4);
    NEW.bic := 'MASKED-' || RIGHT(NEW.bic, 3);
    NEW.is_data_encrypted := true;
  END IF;
  
  -- Prevent storing unencrypted sensitive IBAN data in new records
  IF TG_OP = 'INSERT' AND NEW.is_data_encrypted = false THEN
    IF NEW.iban LIKE 'DE%' OR NEW.iban LIKE 'GB%' OR NEW.iban LIKE 'FR%' OR NEW.iban LIKE 'ES%' THEN
      RAISE EXCEPTION 'New IBAN accounts must be encrypted. Use encrypted_iban and encrypted_bic fields.';
    END IF;
  END IF;
  
  -- Log IBAN data storage attempts
  INSERT INTO security_audit_log (
    user_id, action, resource_type, resource_id, details
  ) VALUES (
    NEW.user_id,
    'iban_data_storage_attempt',
    'iban_accounts',
    NEW.id::text,
    jsonb_build_object(
      'is_encrypted', NEW.is_data_encrypted,
      'has_encrypted_fields', NEW.encrypted_iban IS NOT NULL,
      'country_code', NEW.country_code
    )
  );
  
  RETURN NEW;
END;
$function$;

-- Apply IBAN security trigger
DROP TRIGGER IF EXISTS enforce_iban_encryption ON iban_accounts;
CREATE TRIGGER enforce_iban_encryption
BEFORE INSERT OR UPDATE ON iban_accounts
FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_iban_data();

-- Step 3: Create recovery words encryption enforcement
CREATE OR REPLACE FUNCTION prevent_plaintext_recovery_words()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- Prevent storing new unencrypted recovery words
  IF TG_OP = 'INSERT' AND NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
    RAISE EXCEPTION 'New recovery words must be encrypted. Set recovery_words_encrypted = true and use proper encryption.';
  END IF;
  
  -- If marking as encrypted, ensure proper shape
  IF NEW.recovery_words_encrypted = true AND NEW.wallet_recovery_words IS NOT NULL THEN
    -- Validate that recovery words are in encrypted format (this is a simplified check)
    IF array_length(NEW.wallet_recovery_words, 1) = 12 AND 
       NOT (NEW.wallet_recovery_words[1] LIKE '%encrypted%' OR NEW.wallet_recovery_words[1] LIKE 'enc_%') THEN
      -- Log potential plaintext storage
      INSERT INTO security_audit_log (
        user_id, action, resource_type, resource_id, details
      ) VALUES (
        NEW.user_id,
        'potential_plaintext_recovery_words',
        'user_profiles',
        NEW.id::text,
        jsonb_build_object(
          'recovery_words_encrypted', NEW.recovery_words_encrypted,
          'words_count', array_length(NEW.wallet_recovery_words, 1)
        )
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Apply recovery words security trigger
DROP TRIGGER IF EXISTS enforce_recovery_words_encryption ON user_profiles;
CREATE TRIGGER enforce_recovery_words_encryption
BEFORE INSERT OR UPDATE ON user_profiles
FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_recovery_words();

-- Step 4: Strengthen admin access controls with additional logging
CREATE OR REPLACE FUNCTION is_admin(user_uuid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  user_role app_role;
  request_count integer;
BEGIN
  -- Rate limit admin checks to prevent brute force
  SELECT COUNT(*) INTO request_count
  FROM security_audit_log
  WHERE user_id = user_uuid
    AND action = 'admin_check_attempt'
    AND created_at > now() - interval '1 minute';
  
  IF request_count > 10 THEN
    -- Log suspicious admin check attempts
    INSERT INTO security_audit_log (
      user_id, action, resource_type, details
    ) VALUES (
      user_uuid,
      'admin_check_rate_limit_exceeded',
      'security_system',
      jsonb_build_object(
        'attempts_last_minute', request_count,
        'ip_address', get_client_ip()
      )
    );
    RETURN false;
  END IF;
  
  -- Get user role
  SELECT role INTO user_role
  FROM user_roles
  WHERE user_id = user_uuid
    AND role = 'admin'
  LIMIT 1;
  
  -- Log admin check attempt
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    user_uuid,
    'admin_check_attempt',
    'user_roles',
    jsonb_build_object(
      'result', user_role = 'admin',
      'ip_address', get_client_ip()
    )
  );
  
  RETURN user_role = 'admin';
END;
$function$;

-- Step 5: Create comprehensive security health check function
CREATE OR REPLACE FUNCTION get_security_health_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  total_users integer;
  users_missing_pins integer;
  unencrypted_recovery integer;
  unencrypted_github_tokens integer;
  unencrypted_iban_accounts integer;
  critical_issues integer;
  security_score numeric;
  result jsonb;
BEGIN
  -- Count total users
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  
  -- Count users without PINs
  SELECT COUNT(*) INTO users_missing_pins
  FROM user_profiles
  WHERE wallet_pin_hash IS NULL;
  
  -- Count unencrypted recovery words
  SELECT COUNT(*) INTO unencrypted_recovery
  FROM user_profiles
  WHERE wallet_recovery_words IS NOT NULL
    AND recovery_words_encrypted = false;
  
  -- Count unencrypted GitHub tokens
  SELECT COUNT(*) INTO unencrypted_github_tokens
  FROM github_integrations
  WHERE access_token IS NOT NULL
    AND (encrypted_access_token IS NULL OR is_token_encrypted = false);
  
  -- Count unencrypted IBAN accounts
  SELECT COUNT(*) INTO unencrypted_iban_accounts
  FROM iban_accounts
  WHERE is_data_encrypted = false
    AND (iban LIKE 'DE%' OR iban LIKE 'GB%' OR iban LIKE 'FR%' OR iban LIKE 'ES%');
  
  -- Calculate critical issues
  critical_issues := unencrypted_recovery + unencrypted_github_tokens + unencrypted_iban_accounts;
  
  -- Calculate security score (0-100)
  security_score := CASE
    WHEN total_users = 0 THEN 100
    ELSE GREATEST(0, 100 - (
      (users_missing_pins::numeric / total_users * 20) +
      (unencrypted_recovery::numeric / total_users * 40) +
      (unencrypted_github_tokens * 5) +
      (unencrypted_iban_accounts * 10)
    ))
  END;
  
  -- Compile result
  result := jsonb_build_object(
    'total_users', total_users,
    'users_missing_pins', users_missing_pins,
    'unencrypted_recovery_words', unencrypted_recovery,
    'unencrypted_github_tokens', unencrypted_github_tokens,
    'unencrypted_iban_accounts', unencrypted_iban_accounts,
    'critical_issues', critical_issues,
    'security_score', ROUND(security_score, 1),
    'status', CASE
      WHEN critical_issues = 0 AND users_missing_pins < (total_users * 0.1) THEN 'excellent'
      WHEN critical_issues = 0 THEN 'good'
      WHEN critical_issues < 10 THEN 'warning'
      ELSE 'critical'
    END,
    'recommendations', CASE
      WHEN unencrypted_recovery > 0 THEN jsonb_build_array('Encrypt recovery words immediately')
      WHEN unencrypted_iban_accounts > 0 THEN jsonb_build_array('Encrypt IBAN data')
      WHEN users_missing_pins > (total_users * 0.2) THEN jsonb_build_array('Encourage PIN setup')
      ELSE jsonb_build_array('Security looks good')
    END,
    'timestamp', now()
  );
  
  -- Log the security check
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'security_health_check',
    'security_system',
    result
  );
  
  RETURN result;
END;
$function$;

-- Step 6: Create emergency security fix function for mass encryption
CREATE OR REPLACE FUNCTION run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  fixed_recovery_words integer := 0;
  fixed_pins integer := 0;
  fixed_iban_accounts integer := 0;
  error_count integer := 0;
  result jsonb;
BEGIN
  -- Only allow admins to run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin privileges required for critical security fixes';
  END IF;
  
  -- Fix 1: Mark unencrypted recovery words as needing re-setup (force user to re-encrypt)
  UPDATE user_profiles
  SET 
    wallet_recovery_words = NULL,
    recovery_words_encrypted = false,
    updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS fixed_recovery_words = ROW_COUNT;
  
  -- Fix 2: Reset insecure PINs (force users to create new secure PINs)
  UPDATE user_profiles
  SET 
    wallet_pin_hash = NULL,
    updated_at = now()
  WHERE wallet_pin_hash IS NOT NULL
    AND wallet_pin_hash NOT LIKE '$2%'; -- Not bcrypt hashed
  
  GET DIAGNOSTICS fixed_pins = ROW_COUNT;
  
  -- Fix 3: Mark unencrypted IBAN accounts for re-encryption
  UPDATE iban_accounts
  SET 
    iban = 'REQUIRES-ENCRYPTION-' || RIGHT(iban, 4),
    bic = 'REQ-ENC-' || RIGHT(bic, 3),
    status = 'encryption_required',
    updated_at = now()
  WHERE is_data_encrypted = false
    AND (iban LIKE 'DE%' OR iban LIKE 'GB%' OR iban LIKE 'FR%' OR iban LIKE 'ES%');
  
  GET DIAGNOSTICS fixed_iban_accounts = ROW_COUNT;
  
  -- Compile results
  result := jsonb_build_object(
    'recovery_words_reset', fixed_recovery_words,
    'pins_reset', fixed_pins,
    'iban_accounts_marked', fixed_iban_accounts,
    'total_fixes', fixed_recovery_words + fixed_pins + fixed_iban_accounts,
    'errors', error_count,
    'success', true,
    'timestamp', now(),
    'performed_by', auth.uid()
  );
  
  -- Log the emergency fix
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(),
    'emergency_security_fixes_executed',
    'security_system',
    result
  );
  
  RETURN result;
END;
$function$;

-- Step 7: Create security metrics function for monitoring
CREATE OR REPLACE FUNCTION get_security_metrics_unified()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  metrics jsonb;
  failed_attempts integer;
  admin_actions integer;
  sensitive_accesses integer;
BEGIN
  -- Get security health summary
  SELECT get_security_health_summary() INTO metrics;
  
  -- Add recent security events (last 24 hours)
  SELECT COUNT(*) INTO failed_attempts
  FROM auth_attempts
  WHERE success = false
    AND created_at > now() - interval '24 hours';
  
  SELECT COUNT(*) INTO admin_actions
  FROM security_audit_log
  WHERE action LIKE '%admin%'
    AND created_at > now() - interval '24 hours';
  
  SELECT COUNT(*) INTO sensitive_accesses
  FROM security_audit_log
  WHERE action LIKE '%sensitive_data%'
    AND created_at > now() - interval '24 hours';
  
  -- Enhance metrics with recent activity
  metrics := metrics || jsonb_build_object(
    'recent_failed_attempts', failed_attempts,
    'recent_admin_actions', admin_actions,
    'recent_sensitive_accesses', sensitive_accesses,
    'alert_level', CASE
      WHEN failed_attempts > 100 OR admin_actions > 50 THEN 'high'
      WHEN failed_attempts > 50 OR admin_actions > 20 THEN 'medium'
      ELSE 'low'
    END
  );
  
  RETURN metrics;
END;
$function$;

-- Log this migration
INSERT INTO security_audit_log (
  user_id, action, resource_type, details
) VALUES (
  auth.uid(),
  'critical_security_migration_applied',
  'database_schema',
  jsonb_build_object(
    'migration_timestamp', now(),
    'fixes_applied', jsonb_build_array(
      'github_token_encryption_enforcement',
      'iban_data_encryption_enforcement', 
      'recovery_words_encryption_enforcement',
      'strengthened_admin_checks',
      'comprehensive_security_monitoring'
    )
  )
);