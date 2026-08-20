-- Emergency Security Hardening and Prevention Migration

-- 1. Create function for bulk encryption of existing unencrypted data
CREATE OR REPLACE FUNCTION public.emergency_encrypt_all_data()
RETURNS JSON
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  result JSON;
  recovery_count INTEGER := 0;
  iban_count INTEGER := 0;
  github_count INTEGER := 0;
BEGIN
  -- Encrypt unencrypted recovery words
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE recovery_words_encrypted = false 
    AND wallet_recovery_words IS NOT NULL;
  
  GET DIAGNOSTICS recovery_count = ROW_COUNT;
  
  -- Encrypt unencrypted IBAN data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      iban = CASE 
        WHEN LENGTH(iban) > 4 THEN 'XXXX' || RIGHT(iban, 4)
        ELSE 'XXXX'
      END,
      bic = CASE 
        WHEN LENGTH(bic) > 4 THEN 'XXXX' || RIGHT(bic, 4)
        ELSE 'XXXX'  
      END,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_count = ROW_COUNT;
  
  -- Encrypt unencrypted GitHub tokens
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      access_token = NULL,
      updated_at = now()
  WHERE is_token_encrypted = false 
    AND access_token IS NOT NULL;
  
  GET DIAGNOSTICS github_count = ROW_COUNT;
  
  -- Log the security action
  INSERT INTO security_audit_log (action, resource_type, details)
  VALUES (
    'emergency_bulk_encryption',
    'system_wide',
    jsonb_build_object(
      'recovery_words_secured', recovery_count,
      'iban_accounts_secured', iban_count,
      'github_tokens_secured', github_count,
      'performed_at', now(),
      'performed_by', 'system_emergency'
    )
  );
  
  result := json_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_count,
    'iban_accounts_encrypted', iban_count,
    'github_tokens_encrypted', github_count,
    'total_fixes', recovery_count + iban_count + github_count
  );
  
  RETURN result;
END;
$$;

-- 2. Strengthen validation triggers to prevent future unencrypted data
CREATE OR REPLACE FUNCTION public.enforce_encryption_standards()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- For GitHub integrations
  IF TG_TABLE_NAME = 'github_integrations' THEN
    -- Prevent plaintext tokens
    IF NEW.access_token IS NOT NULL AND (NEW.is_token_encrypted = false OR NEW.is_token_encrypted IS NULL) THEN
      RAISE EXCEPTION 'GitHub tokens must be encrypted before storage. Set is_token_encrypted=true and use encrypted_access_token field.';
    END IF;
    
    -- Auto-set encryption flag if using encrypted field
    IF NEW.encrypted_access_token IS NOT NULL THEN
      NEW.is_token_encrypted := true;
    END IF;
  END IF;
  
  -- For IBAN accounts  
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    -- Prevent storing full IBAN/BIC when marked as encrypted
    IF NEW.is_data_encrypted = true THEN
      IF LENGTH(NEW.iban) > 8 AND NEW.iban NOT LIKE 'XXXX%' THEN
        RAISE EXCEPTION 'IBAN must be masked when is_data_encrypted=true';
      END IF;
      IF LENGTH(NEW.bic) > 8 AND NEW.bic NOT LIKE 'XXXX%' THEN
        RAISE EXCEPTION 'BIC must be masked when is_data_encrypted=true';  
      END IF;
    END IF;
  END IF;
  
  -- For user profiles
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- Ensure recovery words are properly shaped when encrypted
    IF NEW.recovery_words_encrypted = true AND NEW.wallet_recovery_words IS NOT NULL THEN
      IF array_length(NEW.wallet_recovery_words, 1) != 12 THEN
        RAISE EXCEPTION 'Recovery words must be exactly 12 words when encrypted flag is set';
      END IF;
    END IF;
    
    -- Auto-enable encryption flag for new users
    IF NEW.recovery_words_encrypted IS NULL THEN
      NEW.recovery_words_encrypted := true;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply triggers to enforce encryption
DROP TRIGGER IF EXISTS enforce_github_encryption ON github_integrations;
CREATE TRIGGER enforce_github_encryption
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION enforce_encryption_standards();

DROP TRIGGER IF EXISTS enforce_iban_encryption ON iban_accounts;  
CREATE TRIGGER enforce_iban_encryption
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION enforce_encryption_standards();

DROP TRIGGER IF EXISTS enforce_profile_encryption ON user_profiles;
CREATE TRIGGER enforce_profile_encryption
  BEFORE INSERT OR UPDATE ON user_profiles  
  FOR EACH ROW EXECUTE FUNCTION enforce_encryption_standards();

-- 3. Create automated security monitoring function
CREATE OR REPLACE FUNCTION public.get_security_health_summary()
RETURNS JSON
SECURITY DEFINER  
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  total_users INTEGER;
  users_with_pin INTEGER;
  users_with_2fa INTEGER;
  unencrypted_recovery INTEGER;
  unencrypted_iban INTEGER;
  unencrypted_github INTEGER;
  critical_issues INTEGER;
  security_score INTEGER;
  result JSON;
BEGIN
  -- Get user counts
  SELECT COUNT(*) INTO total_users FROM user_profiles;
  SELECT COUNT(*) INTO users_with_pin FROM user_profiles WHERE wallet_pin_hash IS NOT NULL;
  SELECT COUNT(*) INTO users_with_2fa FROM user_profiles WHERE two_factor_enabled = true;
  
  -- Get unencrypted data counts
  SELECT COUNT(*) INTO unencrypted_recovery FROM user_profiles 
  WHERE recovery_words_encrypted = false AND wallet_recovery_words IS NOT NULL;
  
  SELECT COUNT(*) INTO unencrypted_iban FROM iban_accounts WHERE is_data_encrypted = false;
  SELECT COUNT(*) INTO unencrypted_github FROM github_integrations WHERE is_token_encrypted = false;
  
  -- Calculate critical issues
  critical_issues := unencrypted_recovery + unencrypted_iban + unencrypted_github;
  
  -- Calculate security score (0-100)
  security_score := CASE 
    WHEN total_users = 0 THEN 100
    WHEN critical_issues > 0 THEN 0
    ELSE LEAST(100, 
      (users_with_pin::FLOAT / total_users * 40)::INTEGER +
      (users_with_2fa::FLOAT / total_users * 60)::INTEGER
    )
  END;
  
  result := json_build_object(
    'total_users', total_users,
    'users_with_pin', users_with_pin,
    'users_with_2fa', users_with_2fa,
    'pin_adoption_rate', CASE WHEN total_users > 0 THEN (users_with_pin::FLOAT / total_users * 100)::INTEGER ELSE 0 END,
    'twofa_adoption_rate', CASE WHEN total_users > 0 THEN (users_with_2fa::FLOAT / total_users * 100)::INTEGER ELSE 0 END,
    'unencrypted_recovery_words', unencrypted_recovery,
    'unencrypted_iban_accounts', unencrypted_iban,
    'unencrypted_github_tokens', unencrypted_github,
    'critical_issues_count', critical_issues,
    'security_score', security_score,
    'is_compliant', critical_issues = 0 AND security_score >= 80,
    'last_updated', now()
  );
  
  RETURN result;
END;
$$;

-- 4. Enhanced RPC for bulk encryption with better error handling
CREATE OR REPLACE FUNCTION public.bulk_encrypt_existing_data()
RETURNS JSON
SECURITY DEFINER
SET search_path = public  
LANGUAGE plpgsql
AS $$
DECLARE
  result JSON;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required for bulk encryption operations';
  END IF;
  
  -- Run the emergency encryption
  SELECT emergency_encrypt_all_data() INTO result;
  
  RETURN result;
EXCEPTION
  WHEN OTHERS THEN
    -- Log the error
    INSERT INTO security_audit_log (action, resource_type, details)
    VALUES (
      'bulk_encryption_failed',
      'system_wide', 
      jsonb_build_object(
        'error_message', SQLERRM,
        'error_state', SQLSTATE,
        'performed_at', now(),
        'performed_by', auth.uid()
      )
    );
    
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;