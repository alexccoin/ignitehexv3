-- Fix all remaining function search path issues
-- Update existing functions that may not have SET search_path
CREATE OR REPLACE FUNCTION public.mark_user_data_encrypted(user_id_param uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  updated_profiles integer := 0;
  updated_github integer := 0;
  updated_iban integer := 0;
  result jsonb;
BEGIN
  -- Only allow users to mark their own data as encrypted
  IF auth.uid() != user_id_param THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied');
  END IF;

  -- Mark user profile recovery words as encrypted
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE user_id = user_id_param 
  AND wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS updated_profiles = ROW_COUNT;

  -- Mark GitHub tokens as encrypted
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE user_id = user_id_param 
  AND access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  GET DIAGNOSTICS updated_github = ROW_COUNT;

  -- Mark IBAN data as encrypted
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE user_id = user_id_param 
  AND is_data_encrypted = false;
  
  GET DIAGNOSTICS updated_iban = ROW_COUNT;

  -- Log the security action
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    user_id_param, 
    'user_data_marked_encrypted', 
    'security_system',
    jsonb_build_object(
      'profiles_updated', updated_profiles,
      'github_tokens_updated', updated_github,
      'iban_accounts_updated', updated_iban,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'profiles_updated', updated_profiles,
    'github_tokens_updated', updated_github,
    'iban_accounts_updated', updated_iban,
    'timestamp', now()
  );
  
  RETURN result;
END;
$$;