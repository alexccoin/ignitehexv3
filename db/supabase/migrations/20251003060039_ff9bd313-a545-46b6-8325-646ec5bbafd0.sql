-- ============================================================================
-- COMPREHENSIVE SECURITY FIX: RLS Policies & Data Protection
-- Fixes: Critical exposure of PII, payment data, and audit logs
-- ============================================================================

-- 1. SECURE user_profiles table - Currently exposes all customer PII publicly
-- ============================================================================
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.user_profiles;
DROP POLICY IF EXISTS "Public read access to profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Anyone can view profiles" ON public.user_profiles;

-- Users can only view their own profile
CREATE POLICY "Users view own profile secure"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Admins can view all profiles
CREATE POLICY "Admins view all profiles secure"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Users can only insert their own profile
CREATE POLICY "Users insert own profile secure"
ON public.user_profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can only update their own profile
CREATE POLICY "Users update own profile secure"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Admins can update any profile
CREATE POLICY "Admins update all profiles secure"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- 2. SECURE voucher_redemptions table - Currently exposes payment info
-- ============================================================================
DROP POLICY IF EXISTS "Public can view vouchers" ON public.voucher_redemptions;
DROP POLICY IF EXISTS "Anyone can see redemptions" ON public.voucher_redemptions;

-- Users can only view their own voucher redemptions
CREATE POLICY "Users view own vouchers secure"
ON public.voucher_redemptions
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Admins can view all voucher redemptions
CREATE POLICY "Admins view all vouchers secure"
ON public.voucher_redemptions
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Users can insert their own voucher redemptions
CREATE POLICY "Users insert own vouchers secure"
ON public.voucher_redemptions
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can update their own pending vouchers
CREATE POLICY "Users update own pending vouchers secure"
ON public.voucher_redemptions
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id AND status = 'pending')
WITH CHECK (auth.uid() = user_id);

-- Admins can update any voucher
CREATE POLICY "Admins update all vouchers secure"
ON public.voucher_redemptions
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- 3. SECURE security_audit_log table - Prevent exposure of vulnerabilities
-- ============================================================================
DROP POLICY IF EXISTS "Public can read audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "Anyone can view logs" ON public.security_audit_log;

-- Only admins can view security audit logs
CREATE POLICY "Only admins view audit logs secure"
ON public.security_audit_log
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- System can always insert audit logs (SECURITY DEFINER functions)
CREATE POLICY "System inserts audit logs secure"
ON public.security_audit_log
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Only admins can delete old audit logs (for maintenance)
CREATE POLICY "Admins delete audit logs secure"
ON public.security_audit_log
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- 4. Add validation trigger to prevent plaintext sensitive data
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_sensitive_data_encryption()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate user_profiles sensitive data
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- Ensure recovery words are encrypted if present
    IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
      RAISE EXCEPTION 'Security violation: Recovery words must be encrypted before storage';
    END IF;
    
    -- Ensure PIN is hashed if present
    IF NEW.wallet_pin_hash IS NOT NULL AND NEW.wallet_pin_hash NOT LIKE '$2%' THEN
      RAISE EXCEPTION 'Security violation: Wallet PIN must be hashed before storage';
    END IF;
  END IF;
  
  -- Validate IBAN accounts encryption
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF NEW.is_data_encrypted = false THEN
      -- Ensure IBAN/BIC are masked if not encrypted
      IF NEW.iban !~ '^\*+' OR NEW.bic !~ '^\*+' THEN
        RAISE EXCEPTION 'Security violation: IBAN/BIC must be masked or encrypted';
      END IF;
    END IF;
  END IF;
  
  -- Validate GitHub tokens encryption
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
      RAISE EXCEPTION 'Security violation: GitHub access tokens must be encrypted';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply validation triggers to sensitive tables
DROP TRIGGER IF EXISTS validate_user_profile_data ON public.user_profiles;
CREATE TRIGGER validate_user_profile_data
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_sensitive_data_encryption();

DROP TRIGGER IF EXISTS validate_iban_data ON public.iban_accounts;
CREATE TRIGGER validate_iban_data
  BEFORE INSERT OR UPDATE ON public.iban_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_sensitive_data_encryption();

DROP TRIGGER IF EXISTS validate_github_token_data ON public.github_integrations;
CREATE TRIGGER validate_github_token_data
  BEFORE INSERT OR UPDATE ON public.github_integrations
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_sensitive_data_encryption();

-- 5. Log this security migration
-- ============================================================================
INSERT INTO public.security_audit_log (
  user_id,
  action,
  resource_type,
  details
) VALUES (
  auth.uid(),
  'comprehensive_security_migration_applied',
  'database_security',
  jsonb_build_object(
    'migration', 'comprehensive_rls_and_validation',
    'tables_secured', ARRAY['user_profiles', 'voucher_redemptions', 'security_audit_log'],
    'validation_triggers_added', ARRAY['user_profiles', 'iban_accounts', 'github_integrations'],
    'timestamp', now(),
    'severity', 'critical_fix'
  )
);