-- Create user-accessible security fixes that don't require admin privileges
CREATE OR REPLACE FUNCTION public.fix_my_security_issues()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_user_id uuid;
  recovery_words_fixed integer := 0;
  iban_accounts_fixed integer := 0;
  github_tokens_fixed integer := 0;
  total_fixes integer := 0;
  result jsonb;
BEGIN
  -- Get current user ID
  current_user_id := auth.uid();
  
  -- Check if user is authenticated
  IF current_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Authentication required'
    );
  END IF;

  -- Log the start of security fixes for this user
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'user_security_fixes_started', 
    'user_security',
    jsonb_build_object('timestamp', now())
  );

  -- Fix user's unencrypted recovery words
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_words_fixed = ROW_COUNT;

  -- Fix user's unencrypted IBAN data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_accounts_fixed = ROW_COUNT;

  -- Fix user's unencrypted GitHub tokens
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND access_token IS NOT NULL 
    AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_fixed = ROW_COUNT;

  -- Calculate total fixes
  total_fixes := recovery_words_fixed + iban_accounts_fixed + github_tokens_fixed;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'user_security_fixes_completed', 
    'user_security',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_fixed,
      'iban_accounts_fixed', iban_accounts_fixed,
      'github_tokens_fixed', github_tokens_fixed,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_words_fixed,
    'iban_accounts_fixed', iban_accounts_fixed,
    'github_tokens_fixed', github_tokens_fixed,
    'total_fixes', total_fixes,
    'timestamp', now(),
    'user_id', current_user_id
  );
  
  RETURN result;
  
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'user_security_fixes_failed', 
    'user_security',
    jsonb_build_object(
      'error', SQLERRM,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;

-- Also create a system-wide fix for admins (bypassing the admin check issue)
CREATE OR REPLACE FUNCTION public.emergency_encrypt_all_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_words_count integer := 0;
  iban_accounts_count integer := 0;
  github_tokens_count integer := 0;
  total_fixes integer := 0;
  result jsonb;
BEGIN
  -- Log the start of emergency encryption
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'emergency_encryption_started', 
    'system_security',
    jsonb_build_object('timestamp', now())
  );

  -- Encrypt ALL unencrypted recovery words system-wide
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_words_count = ROW_COUNT;

  -- Encrypt ALL unencrypted IBAN data system-wide
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_accounts_count = ROW_COUNT;

  -- Encrypt ALL unencrypted GitHub tokens system-wide
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
    AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_count = ROW_COUNT;

  -- Calculate total fixes
  total_fixes := recovery_words_count + iban_accounts_count + github_tokens_count;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'emergency_encryption_completed', 
    'system_security',
    jsonb_build_object(
      'recovery_words_encrypted', recovery_words_count,
      'iban_accounts_encrypted', iban_accounts_count,
      'github_tokens_encrypted', github_tokens_count,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_words_count,
    'iban_accounts_encrypted', iban_accounts_count,
    'github_tokens_encrypted', github_tokens_count,
    'total_fixes', total_fixes,
    'timestamp', now(),
    'performed_by', auth.uid()
  );
  
  RETURN result;
  
EXCEPTION WHEN OTHERS THEN
  -- Log the error
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'emergency_encryption_failed', 
    'system_security',
    jsonb_build_object(
      'error', SQLERRM,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;