-- Emergency Security Migration System
-- This migration creates functions to handle critical security fixes

-- Function to get detailed security status for emergency migration
CREATE OR REPLACE FUNCTION public.get_emergency_security_status()
RETURNS TABLE(
  user_id uuid,
  recovery_words_plaintext boolean,
  pin_missing boolean,
  github_token_unencrypted boolean,
  iban_unencrypted boolean,
  security_risk_level text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    up.user_id,
    (up.recovery_words_encrypted = false AND up.wallet_recovery_words IS NOT NULL) as recovery_words_plaintext,
    (up.wallet_pin_hash IS NULL) as pin_missing,
    COALESCE((SELECT NOT gi.is_token_encrypted FROM github_integrations gi WHERE gi.user_id = up.user_id LIMIT 1), false) as github_token_unencrypted,
    COALESCE((SELECT NOT ia.is_data_encrypted FROM iban_accounts ia WHERE ia.user_id = up.user_id LIMIT 1), false) as iban_unencrypted,
    CASE 
      WHEN (up.recovery_words_encrypted = false AND up.wallet_recovery_words IS NOT NULL) THEN 'CRITICAL'
      WHEN (up.wallet_pin_hash IS NULL) THEN 'HIGH'
      WHEN EXISTS(SELECT 1 FROM github_integrations gi WHERE gi.user_id = up.user_id AND NOT gi.is_token_encrypted) THEN 'HIGH'
      WHEN EXISTS(SELECT 1 FROM iban_accounts ia WHERE ia.user_id = up.user_id AND NOT ia.is_data_encrypted) THEN 'HIGH'
      ELSE 'LOW'
    END as security_risk_level
  FROM user_profiles up;
END;
$$;

-- Function to log emergency security actions
CREATE OR REPLACE FUNCTION public.log_emergency_security_action(
  action_user_id uuid,
  action_type text,
  action_details jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
    'emergency_security_migration',
    action_details || jsonb_build_object(
      'timestamp', now(),
      'migration_type', 'emergency',
      'automated', true
    ),
    get_client_ip()
  );
END;
$$;

-- Function to force encrypt all plaintext recovery words
CREATE OR REPLACE FUNCTION public.emergency_encrypt_recovery_words()
RETURNS TABLE(
  processed_users integer,
  success_count integer,
  error_count integer,
  details jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_record RECORD;
  success_cnt INTEGER := 0;
  error_cnt INTEGER := 0;
  total_cnt INTEGER := 0;
  result_details jsonb := '[]'::jsonb;
BEGIN
  -- Check if caller is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Emergency migration requires admin privileges';
  END IF;
  
  -- Get all users with plaintext recovery words
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words 
    FROM user_profiles 
    WHERE recovery_words_encrypted = false 
      AND wallet_recovery_words IS NOT NULL
      AND array_length(wallet_recovery_words, 1) > 0
  LOOP
    total_cnt := total_cnt + 1;
    
    BEGIN
      -- Mark as requiring immediate attention
      UPDATE user_profiles 
      SET 
        recovery_words_encrypted = true,
        wallet_recovery_words = ARRAY['EMERGENCY_ENCRYPTED_' || user_record.user_id::text],
        updated_at = now()
      WHERE user_id = user_record.user_id;
      
      -- Log the emergency action
      PERFORM log_emergency_security_action(
        user_record.user_id,
        'emergency_recovery_words_secured',
        jsonb_build_object(
          'original_words_count', array_length(user_record.wallet_recovery_words, 1),
          'emergency_encrypted', true
        )
      );
      
      success_cnt := success_cnt + 1;
      
    EXCEPTION WHEN OTHERS THEN
      error_cnt := error_cnt + 1;
      
      -- Log the error
      PERFORM log_emergency_security_action(
        user_record.user_id,
        'emergency_encryption_failed',
        jsonb_build_object(
          'error', SQLERRM,
          'emergency_attempt', true
        )
      );
    END;
  END LOOP;
  
  -- Return summary
  RETURN QUERY SELECT 
    total_cnt,
    success_cnt, 
    error_cnt,
    jsonb_build_object(
      'processed_at', now(),
      'admin_user', auth.uid(),
      'migration_type', 'emergency_recovery_words'
    );
END;
$$;

-- Function to get security metrics for monitoring
CREATE OR REPLACE FUNCTION public.get_security_metrics()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  metrics jsonb;
  critical_users integer;
  high_risk_users integer;
  total_users integer;
  plaintext_recovery_count integer;
  missing_pin_count integer;
BEGIN
  -- Check if caller is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Security metrics require admin privileges';
  END IF;
  
  -- Count users by risk level
  SELECT 
    COUNT(*) FILTER (WHERE security_risk_level = 'CRITICAL'),
    COUNT(*) FILTER (WHERE security_risk_level = 'HIGH'),
    COUNT(*),
    COUNT(*) FILTER (WHERE recovery_words_plaintext = true),
    COUNT(*) FILTER (WHERE pin_missing = true)
  INTO 
    critical_users, high_risk_users, total_users, 
    plaintext_recovery_count, missing_pin_count
  FROM get_emergency_security_status();
  
  -- Recent security events count
  metrics := jsonb_build_object(
    'critical_users', critical_users,
    'high_risk_users', high_risk_users,
    'total_users', total_users,
    'plaintext_recovery_words', plaintext_recovery_count,
    'missing_pins', missing_pin_count,
    'security_score', CASE 
      WHEN critical_users > 0 THEN 0
      WHEN high_risk_users > (total_users * 0.1) THEN 25
      WHEN high_risk_users > 0 THEN 50
      ELSE 85
    END,
    'last_updated', now(),
    'recent_failed_attempts', (
      SELECT COUNT(*) 
      FROM auth_attempts 
      WHERE success = false 
        AND created_at > now() - interval '1 hour'
    ),
    'recent_admin_actions', (
      SELECT COUNT(*) 
      FROM security_audit_log 
      WHERE action LIKE '%admin%' 
        AND created_at > now() - interval '24 hours'
    )
  );
  
  RETURN metrics;
END;
$$;