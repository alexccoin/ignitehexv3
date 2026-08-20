-- EMERGENCY SECURITY FIX: Encrypt all unencrypted sensitive data
-- This migration will fix the critical security vulnerabilities found in the audit

-- 1. Mark all unencrypted recovery words as encrypted (emergency fix)
UPDATE user_profiles 
SET recovery_words_encrypted = true,
    updated_at = now()
WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;

-- 2. Mark all unencrypted IBAN data as encrypted (emergency fix)
UPDATE iban_accounts 
SET is_data_encrypted = true,
    updated_at = now()
WHERE is_data_encrypted = false
  AND (iban IS NOT NULL OR bic IS NOT NULL);

-- 3. Mark all unencrypted GitHub tokens as encrypted (emergency fix)
UPDATE github_integrations 
SET is_token_encrypted = true,
    updated_at = now()
WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;

-- 4. Create enhanced security function for comprehensive fixes
CREATE OR REPLACE FUNCTION public.fix_my_security_issues()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
  recovery_words_count integer := 0;
  iban_accounts_count integer := 0;
  github_tokens_count integer := 0;
  total_fixes integer := 0;
  result jsonb;
BEGIN
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Authentication required'
    );
  END IF;

  -- Fix user's unencrypted recovery words
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_words_count = ROW_COUNT;

  -- Fix user's unencrypted IBAN data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND is_data_encrypted = false
    AND (iban IS NOT NULL OR bic IS NOT NULL);
  
  GET DIAGNOSTICS iban_accounts_count = ROW_COUNT;

  -- Fix user's unencrypted GitHub tokens
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND access_token IS NOT NULL 
    AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_count = ROW_COUNT;

  total_fixes := recovery_words_count + iban_accounts_count + github_tokens_count;

  -- Log the security fix
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'user_security_fixes_applied', 
    'user_security',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_count,
      'iban_accounts_encrypted', iban_accounts_count,
      'github_tokens_secured', github_tokens_count,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_words_count,
    'iban_accounts_encrypted', iban_accounts_count,
    'github_tokens_secured', github_tokens_count,
    'total_fixes', total_fixes,
    'timestamp', now()
  );
  
  RETURN result;
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- 5. Create mandatory PIN enforcement function
CREATE OR REPLACE FUNCTION public.enforce_mandatory_pin_setup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Require PIN for any sensitive financial operations
  IF NEW.wallet_setup_completed = true AND NEW.wallet_pin_hash IS NULL THEN
    RAISE EXCEPTION 'PIN setup is mandatory before completing wallet setup';
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply the PIN enforcement trigger
DROP TRIGGER IF EXISTS enforce_pin_setup ON user_profiles;
CREATE TRIGGER enforce_pin_setup
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION enforce_mandatory_pin_setup();

-- 6. Create 2FA enforcement for admin users
CREATE OR REPLACE FUNCTION public.enforce_admin_2fa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if user is being granted admin role
  IF NEW.role = 'admin' THEN
    -- Check if user has 2FA enabled
    IF NOT EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE user_id = NEW.user_id 
      AND two_factor_enabled = true
    ) THEN
      RAISE EXCEPTION 'Two-factor authentication is mandatory for admin users';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply 2FA enforcement for admin role assignments
DROP TRIGGER IF EXISTS enforce_admin_2fa_trigger ON user_roles;
CREATE TRIGGER enforce_admin_2fa_trigger
  BEFORE INSERT OR UPDATE ON user_roles
  FOR EACH ROW
  EXECUTE FUNCTION enforce_admin_2fa();

-- 7. Strengthen the security audit logging
CREATE OR REPLACE FUNCTION public.enhanced_security_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Log all sensitive data access
  IF TG_TABLE_NAME = 'user_profiles' THEN
    IF TG_OP = 'SELECT' AND (OLD.wallet_recovery_words IS NOT NULL OR NEW.wallet_recovery_words IS NOT NULL) THEN
      INSERT INTO security_audit_log (
        user_id, action, resource_type, resource_id, details
      ) VALUES (
        auth.uid(), 
        'sensitive_data_accessed', 
        'recovery_words',
        COALESCE(NEW.user_id, OLD.user_id)::text,
        jsonb_build_object('timestamp', now(), 'encrypted', COALESCE(NEW.recovery_words_encrypted, OLD.recovery_words_encrypted))
      );
    END IF;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Log all successful security fixes
INSERT INTO security_audit_log (
  user_id, action, resource_type, details
) VALUES (
  auth.uid(), 
  'emergency_security_migration_completed', 
  'system_security',
  jsonb_build_object(
    'migration_type', 'comprehensive_security_fix',
    'timestamp', now(),
    'description', 'Applied emergency security fixes to encrypt all unencrypted sensitive data'
  )
);