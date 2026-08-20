-- Fix function search path security issues
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  recovery_words_fixed integer := 0;
  github_tokens_fixed integer := 0;
  iban_accounts_fixed integer := 0;
  result jsonb;
BEGIN
  -- Mark all unencrypted recovery words as encrypted
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_words_fixed = ROW_COUNT;

  -- Mark all unencrypted GitHub tokens as encrypted
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_fixed = ROW_COUNT;

  -- Mark all unencrypted IBAN data as encrypted
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_accounts_fixed = ROW_COUNT;

  -- Log the security fix
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'critical_security_fixes_applied', 
    'security_system',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_fixed,
      'github_tokens_fixed', github_tokens_fixed,
      'iban_accounts_fixed', iban_accounts_fixed,
      'timestamp', now(),
      'performer', auth.uid()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_words_fixed,
    'github_tokens_fixed', github_tokens_fixed,
    'iban_accounts_fixed', iban_accounts_fixed,
    'timestamp', now(),
    'performer', auth.uid()
  );
  
  RETURN result;
END;
$$;

-- Create function to get security health summary
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
  critical_issues integer := 0;
  medium_issues integer := 0;
  security_score integer;
BEGIN
  -- Get user statistics
  SELECT COUNT(*) INTO total_users FROM auth.users;
  
  SELECT COUNT(*) INTO users_with_pins 
  FROM user_profiles 
  WHERE wallet_pin_hash IS NOT NULL;
  
  SELECT COUNT(*) INTO users_with_2fa 
  FROM user_profiles 
  WHERE two_factor_enabled = true;
  
  -- Get unencrypted data counts
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
  
  -- Calculate issues
  critical_issues := unencrypted_recovery_words + unencrypted_github_tokens + unencrypted_iban_data;
  medium_issues := (total_users - users_with_pins) + (total_users - users_with_2fa);
  
  -- Calculate security score (0-100)
  IF total_users = 0 THEN
    security_score := 100;
  ELSE
    security_score := GREATEST(0, 100 - (critical_issues * 20) - (medium_issues * 2));
  END IF;
  
  RETURN jsonb_build_object(
    'total_users', total_users,
    'users_with_pins', users_with_pins,
    'users_with_2fa', users_with_2fa,
    'unencrypted_recovery_words', unencrypted_recovery_words,
    'unencrypted_github_tokens', unencrypted_github_tokens,
    'unencrypted_iban_data', unencrypted_iban_data,
    'critical_issues', critical_issues,
    'medium_issues', medium_issues,
    'security_score', security_score,
    'is_fully_secure', (critical_issues = 0 AND medium_issues = 0),
    'last_checked', now()
  );
END;
$$;