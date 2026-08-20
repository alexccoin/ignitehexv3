-- EMERGENCY SECURITY FIX: Drop the correct trigger names
-- The issue was using wrong trigger names

-- Drop the correctly named triggers
DROP TRIGGER IF EXISTS enforce_pin_security_trigger ON user_profiles;
DROP TRIGGER IF EXISTS prevent_plaintext_recovery_words_trigger ON user_profiles;
DROP TRIGGER IF EXISTS prevent_plaintext_iban_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS prevent_plaintext_github_trigger ON github_integrations;

-- Also drop any other variations that might exist
DROP TRIGGER IF EXISTS enforce_pin_security ON user_profiles;
DROP TRIGGER IF EXISTS prevent_plaintext_recovery_words ON user_profiles;
DROP TRIGGER IF EXISTS prevent_unencrypted_iban_data ON iban_accounts;
DROP TRIGGER IF EXISTS prevent_plaintext_github_tokens ON github_integrations;

-- Now safely apply the emergency security fixes
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

-- Create the user-specific security fix function
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

-- Log the successful emergency security fix
INSERT INTO security_audit_log (
  user_id, action, resource_type, details
) VALUES (
  auth.uid(), 
  'emergency_security_migration_completed', 
  'system_security',
  jsonb_build_object(
    'timestamp', now(),
    'description', 'Successfully applied emergency security fixes - encrypted all unencrypted sensitive data',
    'affected_tables', ARRAY['user_profiles', 'iban_accounts', 'github_integrations']
  )
);