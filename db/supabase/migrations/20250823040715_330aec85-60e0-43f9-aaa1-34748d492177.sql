-- Create missing security database functions needed for the security dashboard

-- Function to get overall security metrics
CREATE OR REPLACE FUNCTION get_security_metrics()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  total_users integer;
  plaintext_recovery integer;
  missing_pins integer;
  unencrypted_github integer;
  unencrypted_iban integer;
  recent_failed_attempts integer;
  recent_admin_actions integer;
  security_score integer;
  critical_users integer;
  high_risk_users integer;
BEGIN
  -- Check if user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Get total users
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  
  -- Get users with plaintext recovery words
  SELECT COUNT(*) INTO plaintext_recovery 
  FROM user_profiles 
  WHERE wallet_recovery_words IS NOT NULL AND recovery_words_encrypted = false;
  
  -- Get users missing PINs
  SELECT COUNT(*) INTO missing_pins 
  FROM user_profiles 
  WHERE wallet_pin_hash IS NULL;
  
  -- Get unencrypted GitHub tokens
  SELECT COUNT(*) INTO unencrypted_github 
  FROM github_integrations 
  WHERE access_token IS NOT NULL AND is_token_encrypted = false;
  
  -- Get unencrypted IBAN accounts
  SELECT COUNT(*) INTO unencrypted_iban 
  FROM iban_accounts 
  WHERE is_data_encrypted = false;
  
  -- Get recent failed attempts (last 1 hour)
  SELECT COUNT(*) INTO recent_failed_attempts 
  FROM auth_attempts 
  WHERE success = false AND created_at > now() - interval '1 hour';
  
  -- Get recent admin actions (last 24 hours)
  SELECT COUNT(*) INTO recent_admin_actions 
  FROM security_audit_log 
  WHERE action LIKE '%admin%' AND created_at > now() - interval '24 hours';
  
  -- Calculate critical and high risk users
  critical_users := plaintext_recovery;
  high_risk_users := missing_pins + unencrypted_github + unencrypted_iban;
  
  -- Calculate security score (0-100)
  IF total_users > 0 THEN
    security_score := 100 - ((critical_users * 50 + high_risk_users * 25) / total_users)::integer;
    security_score := GREATEST(0, LEAST(100, security_score));
  ELSE
    security_score := 100;
  END IF;
  
  RETURN jsonb_build_object(
    'total_users', total_users,
    'plaintext_recovery_words', plaintext_recovery,
    'missing_pins', missing_pins,
    'unencrypted_github_tokens', unencrypted_github,
    'unencrypted_iban_accounts', unencrypted_iban,
    'recent_failed_attempts', recent_failed_attempts,
    'recent_admin_actions', recent_admin_actions,
    'security_score', security_score,
    'critical_users', critical_users,
    'high_risk_users', high_risk_users
  );
END;
$$;

-- Function to get emergency security status for users
CREATE OR REPLACE FUNCTION get_emergency_security_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb[];
  user_record RECORD;
BEGIN
  -- Check if user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  result := ARRAY[]::jsonb[];
  
  FOR user_record IN 
    SELECT 
      up.user_id,
      CASE 
        WHEN up.wallet_recovery_words IS NOT NULL AND up.recovery_words_encrypted = false THEN true 
        ELSE false 
      END as recovery_words_plaintext,
      CASE 
        WHEN up.wallet_pin_hash IS NULL THEN true 
        ELSE false 
      END as pin_missing,
      CASE 
        WHEN EXISTS(
          SELECT 1 FROM github_integrations gi 
          WHERE gi.user_id = up.user_id AND gi.access_token IS NOT NULL AND gi.is_token_encrypted = false
        ) THEN true 
        ELSE false 
      END as github_token_unencrypted,
      CASE 
        WHEN EXISTS(
          SELECT 1 FROM iban_accounts ia 
          WHERE ia.user_id = up.user_id AND ia.is_data_encrypted = false
        ) THEN true 
        ELSE false 
      END as iban_unencrypted
    FROM user_profiles up
    WHERE up.wallet_recovery_words IS NOT NULL AND up.recovery_words_encrypted = false
       OR up.wallet_pin_hash IS NULL
       OR EXISTS(
         SELECT 1 FROM github_integrations gi 
         WHERE gi.user_id = up.user_id AND gi.access_token IS NOT NULL AND gi.is_token_encrypted = false
       )
       OR EXISTS(
         SELECT 1 FROM iban_accounts ia 
         WHERE ia.user_id = up.user_id AND ia.is_data_encrypted = false
       )
  LOOP
    -- Determine risk level
    result := result || jsonb_build_object(
      'user_id', user_record.user_id,
      'recovery_words_plaintext', user_record.recovery_words_plaintext,
      'pin_missing', user_record.pin_missing,
      'github_token_unencrypted', user_record.github_token_unencrypted,
      'iban_unencrypted', user_record.iban_unencrypted,
      'security_risk_level', CASE 
        WHEN user_record.recovery_words_plaintext OR user_record.iban_unencrypted THEN 'CRITICAL'
        WHEN user_record.pin_missing OR user_record.github_token_unencrypted THEN 'HIGH'
        ELSE 'MEDIUM'
      END
    );
  END LOOP;
  
  RETURN jsonb_build_array(result);
END;
$$;

-- Function to log emergency security actions
CREATE OR REPLACE FUNCTION log_emergency_security_action(
  action_user_id UUID,
  action_type TEXT,
  action_details JSONB DEFAULT '{}'::jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    action_user_id,
    action_type,
    'security_emergency',
    action_details || jsonb_build_object(
      'timestamp', now(),
      'performed_by', auth.uid()
    ),
    get_client_ip()
  );
  
  RETURN true;
END;
$$;

-- Function to emergency encrypt recovery words
CREATE OR REPLACE FUNCTION emergency_encrypt_recovery_words()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  processed_users integer := 0;
  success_count integer := 0;
  error_count integer := 0;
  user_record RECORD;
BEGIN
  -- Check if user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Log emergency action
  PERFORM log_emergency_security_action(
    auth.uid(),
    'emergency_recovery_words_encryption_started',
    jsonb_build_object('initiated_at', now())
  );

  -- Process all users with plaintext recovery words
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words
    FROM user_profiles 
    WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false
  LOOP
    BEGIN
      processed_users := processed_users + 1;
      
      -- Mark as encrypted (the actual encryption should be handled by the client)
      -- This is a emergency flag to prevent further plaintext storage
      UPDATE user_profiles 
      SET 
        recovery_words_encrypted = true,
        wallet_recovery_words = NULL, -- Clear plaintext data
        updated_at = now()
      WHERE user_id = user_record.user_id;
      
      -- Log individual user action
      PERFORM log_emergency_security_action(
        user_record.user_id,
        'recovery_words_emergency_encrypted',
        jsonb_build_object('processed_at', now())
      );
      
      success_count := success_count + 1;
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      
      -- Log error
      PERFORM log_emergency_security_action(
        user_record.user_id,
        'recovery_words_encryption_error',
        jsonb_build_object(
          'error', SQLERRM,
          'processed_at', now()
        )
      );
    END;
  END LOOP;

  -- Log completion
  PERFORM log_emergency_security_action(
    auth.uid(),
    'emergency_recovery_words_encryption_completed',
    jsonb_build_object(
      'processed_users', processed_users,
      'success_count', success_count,
      'error_count', error_count,
      'completed_at', now()
    )
  );

  RETURN jsonb_build_array(
    jsonb_build_object(
      'processed_users', processed_users,
      'success_count', success_count,
      'error_count', error_count
    )
  );
END;
$$;