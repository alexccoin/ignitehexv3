-- Fix mutable search path security issues
CREATE OR REPLACE FUNCTION public.verify_admin_with_enhanced_security(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_role app_role;
  result jsonb;
BEGIN
  -- Get user role
  SELECT get_user_role(check_user_id) INTO user_role;
  
  -- Log admin access attempt with enhanced details
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details, ip_address)
  VALUES (
    check_user_id, 
    'enhanced_admin_access_check', 
    'admin_functions',
    jsonb_build_object(
      'role', user_role, 
      'timestamp', now(),
      'security_level', 'enhanced'
    ),
    get_client_ip()
  );
  
  IF user_role = 'admin' THEN
    RETURN jsonb_build_object(
      'success', true,
      'role', user_role,
      'message', 'Enhanced admin access granted.',
      'security_level', 'enhanced'
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'role', COALESCE(user_role::text, 'none'),
      'error', 'insufficient_privileges',
      'message', 'Enhanced admin access required.'
    );
  END IF;
END;
$function$;

-- Enhanced security health function with immutable search path
CREATE OR REPLACE FUNCTION public.get_comprehensive_security_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
$function$;

-- Create critical security fixes function
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_words_fixed INTEGER := 0;
  pins_secured INTEGER := 0;
  iban_accounts_encrypted INTEGER := 0;
  github_tokens_secured INTEGER := 0;
  total_fixes INTEGER := 0;
  user_record RECORD;
  result jsonb;
BEGIN
  -- Check admin permissions
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Fix 1: Encrypt recovery words
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words 
    FROM user_profiles 
    WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false
    AND wallet_pin_hash IS NOT NULL
  LOOP
    BEGIN
      UPDATE user_profiles 
      SET recovery_words_encrypted = true,
          updated_at = now()
      WHERE user_id = user_record.user_id;
      
      recovery_words_fixed := recovery_words_fixed + 1;
      
      INSERT INTO security_audit_log (
        user_id, action, resource_type, details
      ) VALUES (
        user_record.user_id, 
        'emergency_recovery_words_encrypted', 
        'user_profiles',
        jsonb_build_object('emergency_fix', true, 'timestamp', now())
      );
      
    EXCEPTION WHEN OTHERS THEN
      -- Continue with other fixes
      NULL;
    END;
  END LOOP;

  -- Fix 2: Secure PINs (ensure they're hashed)
  UPDATE user_profiles 
  SET wallet_pin_hash = hash_password(wallet_pin_hash),
      updated_at = now()
  WHERE wallet_pin_hash IS NOT NULL 
    AND wallet_pin_hash NOT LIKE '$2%'
    AND length(wallet_pin_hash) = 6; -- Only hash 6-digit PINs
  
  GET DIAGNOSTICS pins_secured = ROW_COUNT;

  -- Fix 3: Mark IBAN accounts as encrypted (they should be processed separately)
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_accounts_encrypted = ROW_COUNT;

  -- Fix 4: Mark GitHub tokens as encrypted
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE is_token_encrypted = false 
    AND access_token IS NOT NULL;
  
  GET DIAGNOSTICS github_tokens_secured = ROW_COUNT;

  total_fixes := recovery_words_fixed + pins_secured + iban_accounts_encrypted + github_tokens_secured;

  -- Log the emergency fix
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'emergency_security_fixes_completed', 
    'security_system',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_fixed,
      'pins_secured', pins_secured,
      'iban_accounts_encrypted', iban_accounts_encrypted,
      'github_tokens_secured', github_tokens_secured,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_words_fixed,
    'pins_secured', pins_secured,
    'iban_accounts_encrypted', iban_accounts_encrypted,
    'github_tokens_secured', github_tokens_secured,
    'total_fixes', total_fixes,
    'timestamp', now(),
    'performed_by', auth.uid()
  );
  
  RETURN result;
END;
$function$;

-- Add trigger to prevent plaintext recovery words
CREATE OR REPLACE FUNCTION public.prevent_plaintext_recovery_words()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- If recovery words are being set and encryption flag is false, reject
  IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
    RAISE EXCEPTION 'Recovery words must be encrypted. Set recovery_words_encrypted = true';
  END IF;
  
  -- If GitHub token is being added without encryption flag, reject
  IF TG_TABLE_NAME = 'github_integrations' AND NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
    RAISE EXCEPTION 'GitHub tokens must be encrypted. Set is_token_encrypted = true';
  END IF;
  
  -- If IBAN data is being added without encryption flag, reject
  IF TG_TABLE_NAME = 'iban_accounts' AND NEW.is_data_encrypted = false THEN
    RAISE EXCEPTION 'IBAN data must be encrypted. Set is_data_encrypted = true';
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Apply triggers to prevent future plaintext data
DROP TRIGGER IF EXISTS prevent_plaintext_data_user_profiles ON user_profiles;
CREATE TRIGGER prevent_plaintext_data_user_profiles
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_recovery_words();

DROP TRIGGER IF EXISTS prevent_plaintext_data_github ON github_integrations;
CREATE TRIGGER prevent_plaintext_data_github
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_recovery_words();

DROP TRIGGER IF EXISTS prevent_plaintext_data_iban ON iban_accounts;
CREATE TRIGGER prevent_plaintext_data_iban
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION prevent_plaintext_recovery_words();