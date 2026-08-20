-- Phase 1: Critical Security Fixes - Fix Function Parameter Issue

-- Drop and recreate verify_password function with correct parameters
DROP FUNCTION IF EXISTS verify_password(text, text);

CREATE OR REPLACE FUNCTION verify_password(input_password text, stored_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- Handle null inputs
  IF input_password IS NULL OR stored_hash IS NULL THEN
    RETURN false;
  END IF;
  
  -- Check if hash starts with bcrypt signature
  IF stored_hash LIKE '$2a$%' OR stored_hash LIKE '$2b$%' OR stored_hash LIKE '$2x$%' OR stored_hash LIKE '$2y$%' THEN
    RETURN (crypt(input_password, stored_hash) = stored_hash);
  END IF;
  
  -- Legacy plain text comparison (should be migrated)
  RETURN stored_hash = input_password;
END;
$$;

-- Enhanced security health check function
CREATE OR REPLACE FUNCTION run_security_health_check(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  issues jsonb := '[]'::jsonb;
  score integer := 100;
  user_profile record;
  github_tokens_count integer;
  iban_accounts_count integer;
  unencrypted_recovery boolean := false;
  unencrypted_tokens boolean := false;
  unencrypted_iban boolean := false;
  missing_pin boolean := false;
BEGIN
  -- Check if user exists
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = check_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'User not found',
      'security_score', 0
    );
  END IF;

  -- Get user profile
  SELECT * INTO user_profile
  FROM user_profiles 
  WHERE user_id = check_user_id;
  
  -- Check for missing profile
  IF user_profile IS NULL THEN
    issues := issues || jsonb_build_object(
      'type', 'missing_profile',
      'severity', 'critical',
      'description', 'User profile not found'
    );
    score := score - 30;
  ELSE
    -- Check PIN status
    IF user_profile.wallet_pin_hash IS NULL THEN
      missing_pin := true;
      issues := issues || jsonb_build_object(
        'type', 'missing_pin',
        'severity', 'critical',
        'description', 'Wallet PIN not set up'
      );
      score := score - 25;
    END IF;
    
    -- Check recovery words encryption
    IF user_profile.wallet_recovery_words IS NOT NULL AND 
       (user_profile.recovery_words_encrypted = false OR user_profile.recovery_words_encrypted IS NULL) THEN
      unencrypted_recovery := true;
      issues := issues || jsonb_build_object(
        'type', 'unencrypted_recovery',
        'severity', 'critical',
        'description', 'Recovery words stored in plaintext'
      );
      score := score - 30;
    END IF;
  END IF;
  
  -- Check GitHub tokens
  SELECT COUNT(*) INTO github_tokens_count
  FROM github_integrations 
  WHERE user_id = check_user_id 
    AND (is_token_encrypted = false OR is_token_encrypted IS NULL)
    AND access_token IS NOT NULL;
    
  IF github_tokens_count > 0 THEN
    unencrypted_tokens := true;
    issues := issues || jsonb_build_object(
      'type', 'unencrypted_tokens',
      'severity', 'high',
      'description', 'GitHub tokens not encrypted',
      'count', github_tokens_count
    );
    score := score - 20;
  END IF;
  
  -- Check IBAN accounts
  SELECT COUNT(*) INTO iban_accounts_count
  FROM iban_accounts 
  WHERE user_id = check_user_id 
    AND (is_data_encrypted = false OR is_data_encrypted IS NULL);
    
  IF iban_accounts_count > 0 THEN
    unencrypted_iban := true;
    issues := issues || jsonb_build_object(
      'type', 'unencrypted_iban',
      'severity', 'high',
      'description', 'IBAN accounts not encrypted',
      'count', iban_accounts_count
    );
    score := score - 15;
  END IF;
  
  -- Log security check
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (check_user_id, 'security_health_check', 'user_security', 
          jsonb_build_object(
            'score', score,
            'issues_count', jsonb_array_length(issues),
            'unencrypted_recovery', unencrypted_recovery,
            'unencrypted_tokens', unencrypted_tokens,
            'unencrypted_iban', unencrypted_iban,
            'missing_pin', missing_pin
          ));
  
  RETURN jsonb_build_object(
    'success', true,
    'security_score', GREATEST(0, score),
    'issues', issues,
    'summary', jsonb_build_object(
      'critical_issues', (CASE WHEN missing_pin OR unencrypted_recovery THEN 1 ELSE 0 END) +
                        (CASE WHEN user_profile IS NULL THEN 1 ELSE 0 END),
      'high_issues', (CASE WHEN unencrypted_tokens THEN 1 ELSE 0 END) +
                     (CASE WHEN unencrypted_iban THEN 1 ELSE 0 END),
      'total_issues', jsonb_array_length(issues)
    )
  );
END;
$$;

-- System-wide security status function for admins
CREATE OR REPLACE FUNCTION get_system_security_overview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  total_users integer;
  users_without_pins integer;
  users_with_unencrypted_recovery integer;
  unencrypted_github_tokens integer;
  unencrypted_iban_accounts integer;
  critical_issues integer;
  system_score integer;
BEGIN
  -- Check admin permissions
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  
  -- Get total users count
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  
  -- Count users without PINs
  SELECT COUNT(*) INTO users_without_pins 
  FROM user_profiles 
  WHERE wallet_pin_hash IS NULL;
  
  -- Count users with unencrypted recovery words
  SELECT COUNT(*) INTO users_with_unencrypted_recovery
  FROM user_profiles 
  WHERE wallet_recovery_words IS NOT NULL 
    AND (recovery_words_encrypted = false OR recovery_words_encrypted IS NULL);
  
  -- Count unencrypted GitHub tokens
  SELECT COUNT(*) INTO unencrypted_github_tokens
  FROM github_integrations 
  WHERE (is_token_encrypted = false OR is_token_encrypted IS NULL)
    AND access_token IS NOT NULL;
  
  -- Count unencrypted IBAN accounts
  SELECT COUNT(*) INTO unencrypted_iban_accounts
  FROM iban_accounts 
  WHERE (is_data_encrypted = false OR is_data_encrypted IS NULL);
  
  -- Calculate critical issues
  critical_issues := users_without_pins + users_with_unencrypted_recovery;
  
  -- Calculate system security score
  system_score := 100;
  IF total_users > 0 THEN
    system_score := system_score - (users_without_pins * 100 / total_users * 0.3)::integer;
    system_score := system_score - (users_with_unencrypted_recovery * 100 / total_users * 0.4)::integer;
    system_score := system_score - (unencrypted_github_tokens * 10)::integer;
    system_score := system_score - (unencrypted_iban_accounts * 15)::integer;
  END IF;
  
  system_score := GREATEST(0, LEAST(100, system_score));
  
  RETURN jsonb_build_object(
    'total_users', total_users,
    'users_without_pins', users_without_pins,
    'users_with_unencrypted_recovery', users_with_unencrypted_recovery,
    'unencrypted_github_tokens', unencrypted_github_tokens,
    'unencrypted_iban_accounts', unencrypted_iban_accounts,
    'critical_issues', critical_issues,
    'system_security_score', system_score,
    'security_status', CASE 
      WHEN system_score >= 90 THEN 'excellent'
      WHEN system_score >= 75 THEN 'good'
      WHEN system_score >= 50 THEN 'needs_attention'
      ELSE 'critical'
    END,
    'recommendations', CASE
      WHEN critical_issues > 0 THEN jsonb_build_array(
        'Immediately encrypt all plaintext recovery words',
        'Enforce mandatory PIN setup for all users',
        'Migrate weak PIN hashes to bcrypt'
      )
      WHEN unencrypted_github_tokens > 0 OR unencrypted_iban_accounts > 0 THEN jsonb_build_array(
        'Encrypt remaining GitHub tokens',
        'Encrypt remaining IBAN data'
      )
      ELSE jsonb_build_array('Security status is good')
    END
  );
END;
$$;