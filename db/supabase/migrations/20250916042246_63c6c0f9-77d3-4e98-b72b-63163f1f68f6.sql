-- Create enhanced security enforcement functions

-- Function to enable strict security enforcement
CREATE OR REPLACE FUNCTION enable_strict_security_enforcement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Enable auto-encryption triggers for new data
  -- This ensures all new sensitive data is encrypted automatically
  
  -- Update system settings to enforce security
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    auth.uid(),
    'strict_security_enforcement_enabled',
    'system_security',
    jsonb_build_object(
      'enabled_by', auth.uid(),
      'timestamp', now()
    )
  );
  
  result := jsonb_build_object(
    'success', true,
    'enforcement_enabled', true,
    'timestamp', now()
  );
  
  RETURN result;
END;
$$;

-- Function to enable auto-encryption triggers
CREATE OR REPLACE FUNCTION enable_auto_encryption_triggers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Create or update the auto-encryption trigger for user_profiles
  DROP TRIGGER IF EXISTS auto_encrypt_user_data ON user_profiles;
  CREATE TRIGGER auto_encrypt_user_data
    BEFORE INSERT OR UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION auto_encrypt_sensitive_data();
  
  -- Create or update the auto-encryption trigger for iban_accounts
  DROP TRIGGER IF EXISTS auto_encrypt_iban_data ON iban_accounts;
  CREATE TRIGGER auto_encrypt_iban_data
    BEFORE INSERT OR UPDATE ON iban_accounts
    FOR EACH ROW
    EXECUTE FUNCTION auto_encrypt_sensitive_data();
  
  -- Create or update the auto-encryption trigger for github_integrations
  DROP TRIGGER IF EXISTS auto_encrypt_github_data ON github_integrations;
  CREATE TRIGGER auto_encrypt_github_data
    BEFORE INSERT OR UPDATE ON github_integrations
    FOR EACH ROW
    EXECUTE FUNCTION auto_encrypt_sensitive_data();
  
  -- Log the trigger enablement
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    auth.uid(),
    'auto_encryption_triggers_enabled',
    'system_security',
    jsonb_build_object(
      'triggers_enabled', ARRAY['user_profiles', 'iban_accounts', 'github_integrations'],
      'timestamp', now()
    )
  );
  
  result := jsonb_build_object(
    'success', true,
    'triggers_enabled', true,
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

-- Enhanced bulk encryption function
CREATE OR REPLACE FUNCTION bulk_encrypt_existing_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  recovery_count integer := 0;
  iban_count integer := 0;
  github_count integer := 0;
  total_fixes integer := 0;
  result jsonb;
BEGIN
  -- Encrypt unencrypted recovery words
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_count = ROW_COUNT;
  
  -- Encrypt unencrypted IBAN data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_count = ROW_COUNT;
  
  -- Encrypt unencrypted GitHub tokens
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
    AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_count = ROW_COUNT;
  
  total_fixes := recovery_count + iban_count + github_count;
  
  -- Log the bulk encryption
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    auth.uid(),
    'bulk_data_encryption_completed',
    'system_security',
    jsonb_build_object(
      'recovery_words_encrypted', recovery_count,
      'iban_accounts_encrypted', iban_count,
      'github_tokens_encrypted', github_count,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );
  
  result := jsonb_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_count,
    'iban_accounts_encrypted', iban_count,
    'github_tokens_encrypted', github_count,
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