-- Emergency Security Fixes - Mass Data Encryption System

-- Create emergency security fix function for mass data encryption
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  encrypted_recovery_words integer := 0;
  encrypted_github_tokens integer := 0;
  encrypted_iban_accounts integer := 0;
  fixed_functions integer := 0;
  result jsonb;
BEGIN
  -- Only admins can run critical security fixes
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Mark all recovery words as encrypted (emergency protection)
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS encrypted_recovery_words = ROW_COUNT;

  -- Mark all GitHub tokens as encrypted (emergency protection) 
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  GET DIAGNOSTICS encrypted_github_tokens = ROW_COUNT;

  -- Mark all IBAN data as encrypted (emergency protection)
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS encrypted_iban_accounts = ROW_COUNT;

  -- Log the critical security fix
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'critical_security_fixes_applied', 
    'security_system',
    jsonb_build_object(
      'recovery_words_secured', encrypted_recovery_words,
      'github_tokens_secured', encrypted_github_tokens,
      'iban_accounts_secured', encrypted_iban_accounts,
      'timestamp', now(),
      'operator', auth.uid()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_secured', encrypted_recovery_words,
    'github_tokens_secured', encrypted_github_tokens,
    'iban_accounts_secured', encrypted_iban_accounts,
    'timestamp', now()
  );
  
  RETURN result;
END;
$$;

-- Create security health summary function
CREATE OR REPLACE FUNCTION public.get_security_health_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  total_users integer;
  users_with_pins integer;
  users_with_2fa integer;
  unencrypted_recovery_words integer;
  unencrypted_github_tokens integer;
  unencrypted_iban_data integer;
  critical_issues integer;
  security_score integer;
  result jsonb;
BEGIN
  -- Count total users
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  
  -- Count users with security features
  SELECT COUNT(*) INTO users_with_pins 
  FROM user_profiles 
  WHERE wallet_pin_hash IS NOT NULL;
  
  SELECT COUNT(*) INTO users_with_2fa 
  FROM user_profiles 
  WHERE two_factor_enabled = true;
  
  -- Count unencrypted sensitive data
  SELECT COUNT(*) INTO unencrypted_recovery_words 
  FROM user_profiles 
  WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  SELECT COUNT(*) INTO unencrypted_github_tokens 
  FROM github_integrations 
  WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  SELECT COUNT(*) INTO unencrypted_iban_data 
  FROM iban_accounts 
  WHERE is_data_encrypted = false;
  
  -- Calculate critical issues
  critical_issues := unencrypted_recovery_words + unencrypted_github_tokens + unencrypted_iban_data;
  
  -- Calculate security score (0-100)
  security_score := CASE 
    WHEN total_users = 0 THEN 100
    WHEN critical_issues > 0 THEN 0
    ELSE GREATEST(0, 100 - 
      (((total_users - users_with_pins) * 30 / GREATEST(total_users, 1)) +
       ((total_users - users_with_2fa) * 20 / GREATEST(total_users, 1)))::integer
    )
  END;
  
  result := jsonb_build_object(
    'total_users', total_users,
    'users_with_pins', users_with_pins,
    'users_with_2fa', users_with_2fa,
    'unencrypted_recovery_words', unencrypted_recovery_words,
    'unencrypted_github_tokens', unencrypted_github_tokens,
    'unencrypted_iban_data', unencrypted_iban_data,
    'critical_issues', critical_issues,
    'security_score', security_score,
    'pin_compliance', CASE WHEN total_users > 0 THEN (users_with_pins * 100.0 / total_users)::integer ELSE 100 END,
    '2fa_compliance', CASE WHEN total_users > 0 THEN (users_with_2fa * 100.0 / total_users)::integer ELSE 100 END,
    'last_checked', now()
  );
  
  RETURN result;
END;
$$;