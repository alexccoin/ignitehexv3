-- Add user-level security fix function
CREATE OR REPLACE FUNCTION public.fix_my_security_issues()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_user_id uuid;
  recovery_words_fixed integer := 0;
  github_tokens_fixed integer := 0;
  iban_accounts_fixed integer := 0;
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

  -- Log the start of user security fixes
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

  -- Fix user's unencrypted GitHub tokens
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND access_token IS NOT NULL 
    AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_fixed = ROW_COUNT;

  -- Fix user's unencrypted IBAN data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE user_id = current_user_id
    AND is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_accounts_fixed = ROW_COUNT;

  -- Calculate total fixes
  total_fixes := recovery_words_fixed + github_tokens_fixed + iban_accounts_fixed;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'user_security_fixes_completed', 
    'user_security',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_fixed,
      'github_tokens_fixed', github_tokens_fixed,
      'iban_accounts_fixed', iban_accounts_fixed,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_words_fixed,
    'github_tokens_encrypted', github_tokens_fixed,
    'iban_accounts_encrypted', iban_accounts_fixed,
    'total_fixes', total_fixes,
    'timestamp', now(),
    'performed_by', current_user_id
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

-- Add function to enforce mandatory PIN setup
CREATE OR REPLACE FUNCTION public.enforce_mandatory_pin_setup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  users_without_pins integer := 0;
  result jsonb;
BEGIN
  -- Check if user is admin (only admins can run system-wide enforcement)
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Count users without PINs
  SELECT COUNT(*) INTO users_without_pins
  FROM user_profiles
  WHERE wallet_pin_hash IS NULL;

  -- Log enforcement action
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'mandatory_pin_enforcement', 
    'security_system',
    jsonb_build_object(
      'users_without_pins', users_without_pins,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'users_without_pins', users_without_pins,
    'message', 'PIN enforcement tracking enabled',
    'timestamp', now()
  );
  
  RETURN result;
END;
$function$;

-- Add function to enforce mandatory 2FA setup
CREATE OR REPLACE FUNCTION public.enforce_mandatory_2fa_setup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  users_without_2fa integer := 0;
  result jsonb;
BEGIN
  -- Check if user is admin (only admins can run system-wide enforcement)
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Count users without 2FA
  SELECT COUNT(*) INTO users_without_2fa
  FROM user_profiles
  WHERE two_factor_enabled = false OR two_factor_enabled IS NULL;

  -- Log enforcement action
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'mandatory_2fa_enforcement', 
    'security_system',
    jsonb_build_object(
      'users_without_2fa', users_without_2fa,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'users_without_2fa', users_without_2fa,
    'message', '2FA enforcement tracking enabled',
    'timestamp', now()
  );
  
  RETURN result;
END;
$function$;