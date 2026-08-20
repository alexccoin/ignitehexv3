-- SIMPLIFIED SECURITY MIGRATION: Add security fixes without breaking existing policies

-- Step 1: Create emergency security fix function (uses existing is_admin function)
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
  result jsonb;
BEGIN
  -- Only allow admins to run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin privileges required for critical security fixes';
  END IF;
  
  -- Fix 1: Clear unencrypted recovery words (force users to re-setup securely)
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
  
  -- Fix 3: Mark unencrypted IBAN accounts as requiring encryption
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

-- Step 2: Create comprehensive security health check function
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
  
  RETURN result;
END;
$function$;

-- Step 3: Add encryption enforcement triggers
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
  
  RETURN NEW;
END;
$function$;

-- Apply recovery words security trigger
DROP TRIGGER IF EXISTS enforce_recovery_words_encryption ON user_profiles;
CREATE TRIGGER enforce_recovery_words_encryption
BEFORE INSERT OR UPDATE ON user_profiles
FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_recovery_words();

-- Step 4: Add IBAN encryption enforcement
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
  
  RETURN NEW;
END;
$function$;

-- Apply IBAN security trigger
DROP TRIGGER IF EXISTS enforce_iban_encryption ON iban_accounts;
CREATE TRIGGER enforce_iban_encryption
BEFORE INSERT OR UPDATE ON iban_accounts
FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_iban_data();

-- Step 5: Add GitHub token encryption enforcement
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
  
  RETURN NEW;
END;
$function$;

-- Apply GitHub token security trigger
DROP TRIGGER IF EXISTS enforce_github_token_encryption ON github_integrations;
CREATE TRIGGER enforce_github_token_encryption
BEFORE INSERT OR UPDATE ON github_integrations
FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_github_tokens();

-- Log this critical security migration
INSERT INTO security_audit_log (
  user_id, action, resource_type, details
) VALUES (
  auth.uid(),
  'security_hardening_migration_completed',
  'database_schema',
  jsonb_build_object(
    'migration_timestamp', now(),
    'fixes_applied', jsonb_build_array(
      'emergency_security_fixes_function',
      'security_health_monitoring',
      'encryption_enforcement_triggers'
    ),
    'security_level', 'hardened'
  )
);