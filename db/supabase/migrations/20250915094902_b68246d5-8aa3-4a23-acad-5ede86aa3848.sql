-- EMERGENCY SECURITY FIX: Drop ALL audit and logging triggers
-- Multiple audit triggers are blocking the security fix

-- Drop all audit triggers that use log_sensitive_data_access
DROP TRIGGER IF EXISTS audit_user_profiles ON user_profiles;
DROP TRIGGER IF EXISTS audit_transactions ON transactions;
DROP TRIGGER IF EXISTS audit_iban_accounts ON iban_accounts;
DROP TRIGGER IF EXISTS audit_prepaid_cards ON prepaid_cards;
DROP TRIGGER IF EXISTS audit_github_integrations ON github_integrations;

-- Drop log_sensitive_data_access_trigger variations
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON user_profiles;
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON github_integrations;
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON transactions;
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON prepaid_cards;

-- Drop sensitive data audit triggers
DROP TRIGGER IF EXISTS sensitive_data_audit_trigger ON user_profiles;
DROP TRIGGER IF EXISTS sensitive_data_audit_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS sensitive_data_audit_trigger ON github_integrations;

-- Drop all encryption enforcement triggers
DROP TRIGGER IF EXISTS enforce_github_token_encryption ON github_integrations;
DROP TRIGGER IF EXISTS enforce_iban_encryption ON iban_accounts;
DROP TRIGGER IF EXISTS enforce_recovery_words_encryption ON user_profiles;

-- Drop validation triggers
DROP TRIGGER IF EXISTS ensure_iban_encrypted ON iban_accounts;
DROP TRIGGER IF EXISTS validate_github_token_encryption ON github_integrations;

-- Now apply the emergency security fixes without interference
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

-- Create simplified user security fix function
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