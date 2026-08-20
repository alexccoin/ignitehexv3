-- CRITICAL SECURITY FIXES - Phase 1: Immediate Data Protection

-- 1. Strengthen RLS policies for critical tables

-- Fix user_profiles RLS policies - ensure users can only access their own data
DROP POLICY IF EXISTS "Users can view their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can create their own profile" ON public.user_profiles;

CREATE POLICY "Users can view own profile only" ON public.user_profiles
FOR SELECT USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users can update own profile only" ON public.user_profiles  
FOR UPDATE USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users can insert own profile only" ON public.user_profiles
FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

-- Fix transactions RLS policies - strengthen financial data protection
DROP POLICY IF EXISTS "Users can view their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users can insert their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users can update their own transactions" ON public.transactions;

CREATE POLICY "Users view own transactions secure" ON public.transactions
FOR SELECT USING (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users insert own transactions secure" ON public.transactions
FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

CREATE POLICY "Users update own transactions secure" ON public.transactions
FOR UPDATE USING (auth.uid() IS NOT NULL AND auth.uid() = user_id)
WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);

-- 2. Add enhanced security validation triggers

-- Trigger to prevent storing unencrypted recovery words
CREATE OR REPLACE FUNCTION validate_recovery_words_encryption()
RETURNS TRIGGER AS $$
BEGIN
  -- If recovery words are provided, they must be encrypted
  IF NEW.wallet_recovery_words IS NOT NULL AND array_length(NEW.wallet_recovery_words, 1) > 0 THEN
    IF COALESCE(NEW.recovery_words_encrypted, false) = false THEN
      RAISE EXCEPTION 'Recovery words must be encrypted. Use encryption migration first.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ensure_recovery_words_encrypted ON public.user_profiles;
CREATE TRIGGER ensure_recovery_words_encrypted
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION validate_recovery_words_encryption();

-- Trigger to prevent storing unencrypted IBAN data
CREATE OR REPLACE FUNCTION validate_iban_encryption()
RETURNS TRIGGER AS $$
BEGIN
  -- If IBAN data exists and is not marked as encrypted, require encryption
  IF (NEW.iban IS NOT NULL AND NEW.iban != '***ENCRYPTED***') OR 
     (NEW.bic IS NOT NULL AND NEW.bic != '***ENCRYPTED***') THEN
    IF COALESCE(NEW.is_data_encrypted, false) = false THEN
      RAISE EXCEPTION 'IBAN data must be encrypted. Use encryption migration first.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ensure_iban_encrypted ON public.iban_accounts;
CREATE TRIGGER ensure_iban_encrypted
  BEFORE INSERT OR UPDATE ON public.iban_accounts
  FOR EACH ROW EXECUTE FUNCTION validate_iban_encryption();

-- 3. Add security audit logging for sensitive data access

CREATE OR REPLACE FUNCTION log_sensitive_data_access()
RETURNS TRIGGER AS $$
BEGIN
  -- Log all access to sensitive financial and personal data
  IF TG_TABLE_NAME IN ('user_profiles', 'transactions', 'iban_accounts', 'prepaid_cards', 'github_integrations') THEN
    INSERT INTO public.security_audit_log (
      user_id,
      action,
      resource_type,
      resource_id,
      details,
      ip_address
    ) VALUES (
      auth.uid(),
      TG_OP || '_sensitive_data',
      TG_TABLE_NAME,
      COALESCE(NEW.id, OLD.id)::text,
      jsonb_build_object(
        'operation', TG_OP,
        'table', TG_TABLE_NAME,
        'timestamp', now(),
        'has_encrypted_data', CASE 
          WHEN TG_TABLE_NAME = 'user_profiles' THEN COALESCE(NEW.recovery_words_encrypted, OLD.recovery_words_encrypted, false)
          WHEN TG_TABLE_NAME = 'iban_accounts' THEN COALESCE(NEW.is_data_encrypted, OLD.is_data_encrypted, false)
          WHEN TG_TABLE_NAME = 'github_integrations' THEN COALESCE(NEW.is_token_encrypted, OLD.is_token_encrypted, false)
          ELSE false
        END
      ),
      get_client_ip()
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Apply audit logging to all sensitive tables
DROP TRIGGER IF EXISTS audit_user_profiles ON public.user_profiles;
CREATE TRIGGER audit_user_profiles
  AFTER INSERT OR UPDATE OR DELETE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();

DROP TRIGGER IF EXISTS audit_transactions ON public.transactions;
CREATE TRIGGER audit_transactions
  AFTER INSERT OR UPDATE OR DELETE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();

DROP TRIGGER IF EXISTS audit_iban_accounts ON public.iban_accounts;
CREATE TRIGGER audit_iban_accounts
  AFTER INSERT OR UPDATE OR DELETE ON public.iban_accounts
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();

DROP TRIGGER IF EXISTS audit_prepaid_cards ON public.prepaid_cards;
CREATE TRIGGER audit_prepaid_cards
  AFTER INSERT OR UPDATE OR DELETE ON public.prepaid_cards
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();

DROP TRIGGER IF EXISTS audit_github_integrations ON public.github_integrations;
CREATE TRIGGER audit_github_integrations
  AFTER INSERT OR UPDATE OR DELETE ON public.github_integrations
  FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();

-- 4. Create secure data access functions

-- Function to securely retrieve user's own profile data
CREATE OR REPLACE FUNCTION get_user_profile_secure(target_user_id uuid DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  user_id uuid,
  full_name text,
  email_address text,
  str_domain_owned text,
  status account_status,
  user_status user_status,
  wallet_setup_completed boolean,
  recovery_words_encrypted boolean,
  two_factor_enabled boolean,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  requesting_user_id uuid;
BEGIN
  requesting_user_id := auth.uid();
  
  -- Security check: users can only access their own data unless admin
  IF requesting_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  
  IF target_user_id IS NOT NULL AND target_user_id != requesting_user_id THEN
    IF NOT is_admin(requesting_user_id) THEN
      RAISE EXCEPTION 'Access denied: can only access own profile';
    END IF;
  END IF;
  
  -- Use requesting user's ID if no target specified
  IF target_user_id IS NULL THEN
    target_user_id := requesting_user_id;
  END IF;
  
  -- Log the secure access
  INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
  VALUES (requesting_user_id, 'secure_profile_access', 'user_profiles', target_user_id::text, 
          jsonb_build_object('accessed_user', target_user_id, 'is_admin_access', is_admin(requesting_user_id)));
  
  RETURN QUERY
  SELECT 
    up.id,
    up.user_id,
    up.full_name,
    up.email_address,
    up.str_domain_owned,
    up.status,
    up.user_status,
    up.wallet_setup_completed,
    up.recovery_words_encrypted,
    up.two_factor_enabled,
    up.created_at,
    up.updated_at
  FROM user_profiles up
  WHERE up.user_id = target_user_id;
END;
$$;

-- 5. Add emergency data protection measures

-- Function to immediately mask unencrypted sensitive data
CREATE OR REPLACE FUNCTION emergency_mask_unencrypted_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  masked_count jsonb := '{}';
  temp_count integer;
BEGIN
  -- Only admins can run this emergency function
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required for emergency data masking';
  END IF;
  
  -- Log the emergency action
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (auth.uid(), 'emergency_data_masking', 'system', 
          jsonb_build_object('timestamp', now(), 'action', 'emergency_mask_unencrypted_data'));
  
  -- Count and return what was masked
  SELECT COUNT(*) INTO temp_count FROM iban_accounts WHERE is_data_encrypted = false;
  masked_count := jsonb_set(masked_count, '{unencrypted_iban_accounts}', to_jsonb(temp_count));
  
  SELECT COUNT(*) INTO temp_count FROM user_profiles WHERE recovery_words_encrypted = false AND wallet_recovery_words IS NOT NULL;
  masked_count := jsonb_set(masked_count, '{unencrypted_recovery_words}', to_jsonb(temp_count));
  
  SELECT COUNT(*) INTO temp_count FROM github_integrations WHERE is_token_encrypted = false;
  masked_count := jsonb_set(masked_count, '{unencrypted_github_tokens}', to_jsonb(temp_count));
  
  RETURN jsonb_set(masked_count, '{emergency_masking_completed_at}', to_jsonb(now()));
END;
$$;