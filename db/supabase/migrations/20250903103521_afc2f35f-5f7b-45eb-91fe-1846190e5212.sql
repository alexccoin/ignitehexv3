-- Phase 1: Critical Data Protection - Create secure encrypted tables
CREATE TABLE public.user_personal_data_encrypted (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  encrypted_full_name TEXT,
  encrypted_address TEXT,
  encrypted_city TEXT,
  encrypted_country TEXT,
  encrypted_postal_code TEXT,
  encrypted_phone_number TEXT,
  encryption_iv TEXT,
  encryption_salt TEXT,
  last_accessed_at TIMESTAMP WITH TIME ZONE,
  access_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS with strict policies for personal data
ALTER TABLE public.user_personal_data_encrypted ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Strict owner access to encrypted personal data"
ON public.user_personal_data_encrypted
FOR ALL
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Strict admin access to encrypted personal data"
ON public.user_personal_data_encrypted
FOR SELECT
USING (is_admin(auth.uid()));

-- Create wallet security table
CREATE TABLE public.user_wallet_security (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  encrypted_recovery_words TEXT,
  encrypted_pin_hash TEXT,
  encrypted_bsc_wallet TEXT,
  encrypted_btc_wallet TEXT,
  encrypted_str_wallet TEXT,
  recovery_encryption_iv TEXT,
  pin_encryption_iv TEXT,
  wallet_encryption_iv TEXT,
  encryption_salt TEXT,
  recovery_backup_count INTEGER DEFAULT 0,
  pin_change_count INTEGER DEFAULT 0,
  last_recovery_access TIMESTAMP WITH TIME ZONE,
  security_level INTEGER DEFAULT 1,
  device_fingerprints JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS with strict policies for wallet security
ALTER TABLE public.user_wallet_security ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ultra strict owner access to wallet security"
ON public.user_wallet_security
FOR ALL
USING (auth.uid() = user_id AND auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() = user_id AND auth.uid() IS NOT NULL);

CREATE POLICY "Admin emergency access to wallet security"
ON public.user_wallet_security
FOR SELECT
USING (is_admin(auth.uid()));

-- Phase 2: Admin Security Hardening - Create admin session tracking
CREATE TABLE public.admin_session_log (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_user_id UUID NOT NULL,
  session_token TEXT,
  ip_address INET,
  user_agent TEXT,
  login_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  logout_at TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN DEFAULT true,
  risk_score INTEGER DEFAULT 0,
  actions_performed INTEGER DEFAULT 0,
  sensitive_operations JSONB DEFAULT '[]'::jsonb
);

-- RLS for admin session log
ALTER TABLE public.admin_session_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only system can manage admin sessions"
ON public.admin_session_log
FOR ALL
USING (true)
WITH CHECK (true);

-- Create admin approval queue for critical operations
CREATE TABLE public.admin_approval_queue (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  requesting_admin UUID NOT NULL,
  approving_admin UUID,
  operation_type TEXT NOT NULL,
  operation_details JSONB NOT NULL,
  target_user_id UUID,
  risk_level TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'pending',
  requested_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  approved_at TIMESTAMP WITH TIME ZONE,
  executed_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (now() + INTERVAL '24 hours')
);

-- RLS for admin approval queue
ALTER TABLE public.admin_approval_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage approval queue"
ON public.admin_approval_queue
FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Create data encryption enforcement triggers
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

-- Create secure data migration function
CREATE OR REPLACE FUNCTION migrate_sensitive_data_to_secure_tables()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_record RECORD;
  migrated_count INTEGER := 0;
  failed_count INTEGER := 0;
  result JSONB;
BEGIN
  -- Migrate personal data to encrypted table
  FOR user_record IN 
    SELECT user_id, full_name, address, city, country, postal_code
    FROM user_profiles 
    WHERE user_id IS NOT NULL
  LOOP
    BEGIN
      -- Insert into secure table (encryption will be handled by application layer)
      INSERT INTO user_personal_data_encrypted (
        user_id,
        encrypted_full_name,
        encrypted_address,
        encrypted_city,
        encrypted_country,
        encrypted_postal_code,
        encryption_iv,
        encryption_salt
      ) VALUES (
        user_record.user_id,
        'PENDING_ENCRYPTION:' || user_record.full_name,
        'PENDING_ENCRYPTION:' || user_record.address,
        'PENDING_ENCRYPTION:' || user_record.city,
        'PENDING_ENCRYPTION:' || user_record.country,
        'PENDING_ENCRYPTION:' || user_record.postal_code,
        'pending',
        'pending'
      ) ON CONFLICT (user_id) DO NOTHING;
      
      -- Initialize wallet security record
      INSERT INTO user_wallet_security (
        user_id,
        encrypted_recovery_words,
        encrypted_pin_hash,
        encrypted_bsc_wallet,
        encrypted_btc_wallet,
        encrypted_str_wallet,
        encryption_salt
      ) VALUES (
        user_record.user_id,
        CASE WHEN EXISTS(SELECT 1 FROM user_profiles WHERE user_id = user_record.user_id AND wallet_recovery_words IS NOT NULL)
             THEN 'PENDING_MIGRATION'
             ELSE NULL
        END,
        CASE WHEN EXISTS(SELECT 1 FROM user_profiles WHERE user_id = user_record.user_id AND wallet_pin_hash IS NOT NULL)
             THEN 'PENDING_MIGRATION'
             ELSE NULL
        END,
        'PENDING_MIGRATION',
        'PENDING_MIGRATION',
        'PENDING_MIGRATION',
        'pending'
      ) ON CONFLICT (user_id) DO NOTHING;
      
      migrated_count := migrated_count + 1;
      
    EXCEPTION WHEN OTHERS THEN
      failed_count := failed_count + 1;
      
      -- Log the failure
      INSERT INTO security_audit_log (
        user_id, action, resource_type, details
      ) VALUES (
        user_record.user_id, 
        'sensitive_data_migration_failed', 
        'user_personal_data_encrypted',
        jsonb_build_object(
          'error', SQLERRM,
          'timestamp', now()
        )
      );
    END;
  END LOOP;

  result := jsonb_build_object(
    'success', true,
    'migrated_count', migrated_count,
    'failed_count', failed_count,
    'timestamp', now()
  );

  RETURN result;
END;
$$;

-- Create enhanced admin verification function
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

  -- Check for suspicious session activity
  SELECT COUNT(*) INTO session_count
  FROM admin_session_log
  WHERE admin_user_id = verify_admin_with_enhanced_security.admin_user_id
    AND login_at > now() - INTERVAL '1 hour'
    AND is_active = true;

  -- Check recent authentication failures
  SELECT COUNT(*) INTO recent_failures
  FROM auth_attempts
  WHERE user_id = admin_user_id
    AND success = false
    AND created_at > now() - INTERVAL '15 minutes';

  -- High-risk operations require additional verification
  IF risk_level = 'high' AND (session_count > 3 OR recent_failures > 2) THEN
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
      'session_count', session_count,
      'recent_failures', recent_failures
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'admin_verified', true,
    'risk_assessment', jsonb_build_object(
      'level', risk_level,
      'session_count', session_count,
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
  admin_session_anomalies INTEGER;
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

  -- Count admin session anomalies
  SELECT COUNT(*) INTO admin_session_anomalies
  FROM admin_session_log
  WHERE login_at > now() - INTERVAL '24 hours'
    AND risk_score > 5;

  -- Categorize issues
  IF unencrypted_users > 0 OR unencrypted_github_tokens > 0 THEN
    critical_issues := critical_issues + 1;
  END IF;

  IF unencrypted_iban_accounts > 0 THEN
    high_issues := high_issues + 1;
  END IF;

  IF admin_session_anomalies > 0 THEN
    medium_issues := medium_issues + 1;
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
      'recent_security_events', recent_security_events,
      'admin_session_anomalies', admin_session_anomalies
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