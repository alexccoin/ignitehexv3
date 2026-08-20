-- Create only the missing security enhancement functions and triggers
-- (Skip tables that already exist)

-- Create enhanced admin verification function if it doesn't exist
CREATE OR REPLACE FUNCTION verify_admin_with_enhanced_security(
  admin_user_id UUID,
  operation_type TEXT,
  risk_level TEXT DEFAULT 'medium'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_valid_admin BOOLEAN := false;
  session_count INTEGER;
  recent_failures INTEGER;
  result JSONB;
BEGIN
  -- Verify admin status
  IF NOT is_admin(admin_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'insufficient_privileges',
      'message', 'Admin privileges required'
    );
  END IF;

  -- Check recent authentication failures
  SELECT COUNT(*) INTO recent_failures
  FROM auth_attempts
  WHERE user_id = admin_user_id
    AND success = false
    AND created_at > now() - INTERVAL '15 minutes';

  -- High-risk operations require additional verification
  IF risk_level = 'high' AND recent_failures > 2 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'additional_verification_required',
      'message', 'High-risk operation requires additional verification'
    );
  END IF;

  -- Log admin action
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    admin_user_id,
    'enhanced_admin_verification',
    'admin_security',
    jsonb_build_object(
      'operation_type', operation_type,
      'risk_level', risk_level,
      'recent_failures', recent_failures
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'admin_verified', true,
    'risk_assessment', jsonb_build_object(
      'level', risk_level,
      'recent_failures', recent_failures
    )
  );
END;
$$;

-- Create comprehensive security health check function
CREATE OR REPLACE FUNCTION get_comprehensive_security_health()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  unencrypted_users INTEGER;
  unencrypted_github_tokens INTEGER;
  unencrypted_iban_accounts INTEGER;
  recent_security_events INTEGER;
  critical_issues INTEGER := 0;
  high_issues INTEGER := 0;
  medium_issues INTEGER := 0;
  result JSONB;
BEGIN
  -- Count unencrypted recovery words
  SELECT COUNT(*) INTO unencrypted_users
  FROM user_profiles
  WHERE wallet_recovery_words IS NOT NULL AND recovery_words_encrypted = false;

  -- Count unencrypted GitHub tokens
  SELECT COUNT(*) INTO unencrypted_github_tokens
  FROM github_integrations
  WHERE access_token IS NOT NULL AND is_token_encrypted = false;

  -- Count unencrypted IBAN accounts
  SELECT COUNT(*) INTO unencrypted_iban_accounts
  FROM iban_accounts
  WHERE is_data_encrypted = false;

  -- Count recent security events
  SELECT COUNT(*) INTO recent_security_events
  FROM security_audit_log
  WHERE created_at > now() - INTERVAL '24 hours'
    AND action LIKE '%security%';

  -- Categorize issues
  IF unencrypted_users > 0 OR unencrypted_github_tokens > 0 THEN
    critical_issues := critical_issues + 1;
  END IF;

  IF unencrypted_iban_accounts > 0 THEN
    high_issues := high_issues + 1;
  END IF;

  result := jsonb_build_object(
    'overall_status', CASE 
      WHEN critical_issues > 0 THEN 'critical'
      WHEN high_issues > 0 THEN 'high_risk'
      WHEN medium_issues > 0 THEN 'medium_risk'
      ELSE 'healthy'
    END,
    'security_score', GREATEST(0, 100 - (critical_issues * 40) - (high_issues * 20) - (medium_issues * 10)),
    'issues_summary', jsonb_build_object(
      'critical', critical_issues,
      'high', high_issues,
      'medium', medium_issues
    ),
    'detailed_metrics', jsonb_build_object(
      'unencrypted_users', unencrypted_users,
      'unencrypted_github_tokens', unencrypted_github_tokens,
      'unencrypted_iban_accounts', unencrypted_iban_accounts,
      'recent_security_events', recent_security_events
    ),
    'recommendations', CASE
      WHEN critical_issues > 0 THEN jsonb_build_array(
        'Immediately encrypt all recovery words and GitHub tokens',
        'Run emergency security migration',
        'Review admin access patterns'
      )
      WHEN high_issues > 0 THEN jsonb_build_array(
        'Encrypt remaining IBAN accounts',
        'Enhanced monitoring recommended'
      )
      ELSE jsonb_build_array('System security appears healthy')
    END,
    'generated_at', now()
  );

  RETURN result;
END;
$$;

-- Create data encryption enforcement triggers if they don't exist
DROP TRIGGER IF EXISTS enforce_github_token_encryption ON public.github_integrations;
DROP TRIGGER IF EXISTS enforce_iban_encryption ON public.iban_accounts;
DROP TRIGGER IF EXISTS enforce_recovery_words_encryption ON public.user_profiles;

CREATE OR REPLACE FUNCTION enforce_no_plaintext_sensitive_data()
RETURNS TRIGGER AS $$
BEGIN
  -- Prevent plaintext GitHub tokens
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
      RAISE EXCEPTION 'Plaintext GitHub tokens are not allowed. Use encrypted_access_token instead.';
    END IF;
  END IF;

  -- Prevent plaintext IBAN/BIC when encryption is marked as required
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF NEW.is_data_encrypted = true AND (NEW.iban NOT LIKE '****%' OR NEW.bic NOT LIKE '***%') THEN
      RAISE EXCEPTION 'IBAN/BIC must be masked when marked as encrypted.';
    END IF;
  END IF;

  -- Prevent plaintext recovery words when encryption flag is set
  IF TG_TABLE_NAME = 'user_profiles' THEN
    IF NEW.recovery_words_encrypted = true AND NEW.wallet_recovery_words IS NOT NULL THEN
      -- Check if it looks like plaintext (simple heuristic)
      IF array_length(NEW.wallet_recovery_words, 1) > 0 AND 
         length(NEW.wallet_recovery_words[1]) < 50 THEN
        RAISE EXCEPTION 'Recovery words must be properly encrypted when encryption flag is true.';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply enforcement triggers
CREATE TRIGGER enforce_github_token_encryption
  BEFORE INSERT OR UPDATE ON public.github_integrations
  FOR EACH ROW EXECUTE FUNCTION enforce_no_plaintext_sensitive_data();

CREATE TRIGGER enforce_iban_encryption
  BEFORE INSERT OR UPDATE ON public.iban_accounts
  FOR EACH ROW EXECUTE FUNCTION enforce_no_plaintext_sensitive_data();

CREATE TRIGGER enforce_recovery_words_encryption
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION enforce_no_plaintext_sensitive_data();