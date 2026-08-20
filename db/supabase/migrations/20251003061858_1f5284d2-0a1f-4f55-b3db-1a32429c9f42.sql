-- ============================================================================
-- COMPREHENSIVE SECURITY FIX: RLS Policies & Data Protection (Fixed)
-- Fixes: Critical exposure of PII, payment data, and audit logs
-- ============================================================================

-- 1. SECURE user_profiles table - Remove all existing policies first
-- ============================================================================
DO $$ 
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname FROM pg_policies 
        WHERE tablename = 'user_profiles' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_profiles', policy_rec.policyname);
    END LOOP;
END $$;

-- Create new secure policies for user_profiles
CREATE POLICY "Users view own profile secure"
ON public.user_profiles FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins view all profiles secure"
ON public.user_profiles FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "Users insert own profile secure"
ON public.user_profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own profile secure"
ON public.user_profiles FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins update all profiles secure"
ON public.user_profiles FOR UPDATE
TO authenticated
USING (has_role(auth.uid(), 'admin'))
WITH CHECK (has_role(auth.uid(), 'admin'));

-- 2. SECURE voucher_redemptions table
-- ============================================================================
DO $$ 
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname FROM pg_policies 
        WHERE tablename = 'voucher_redemptions' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.voucher_redemptions', policy_rec.policyname);
    END LOOP;
END $$;

CREATE POLICY "Users view own vouchers secure"
ON public.voucher_redemptions FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins view all vouchers secure"
ON public.voucher_redemptions FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "Users insert own vouchers secure"
ON public.voucher_redemptions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own pending vouchers secure"
ON public.voucher_redemptions FOR UPDATE
TO authenticated
USING (auth.uid() = user_id AND status = 'pending')
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins update all vouchers secure"
ON public.voucher_redemptions FOR UPDATE
TO authenticated
USING (has_role(auth.uid(), 'admin'))
WITH CHECK (has_role(auth.uid(), 'admin'));

-- 3. SECURE security_audit_log table
-- ============================================================================
DO $$ 
DECLARE
    policy_rec RECORD;
BEGIN
    FOR policy_rec IN 
        SELECT policyname FROM pg_policies 
        WHERE tablename = 'security_audit_log' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.security_audit_log', policy_rec.policyname);
    END LOOP;
END $$;

CREATE POLICY "Only admins view audit logs secure"
ON public.security_audit_log FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "System inserts audit logs secure"
ON public.security_audit_log FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Admins delete audit logs secure"
ON public.security_audit_log FOR DELETE
TO authenticated
USING (has_role(auth.uid(), 'admin'));

-- 4. Add validation trigger to prevent plaintext sensitive data
-- ============================================================================
CREATE OR REPLACE FUNCTION public.validate_sensitive_data_encryption()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'user_profiles' THEN
    IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
      RAISE EXCEPTION 'Security violation: Recovery words must be encrypted before storage';
    END IF;
    IF NEW.wallet_pin_hash IS NOT NULL AND NEW.wallet_pin_hash NOT LIKE '$2%' THEN
      RAISE EXCEPTION 'Security violation: Wallet PIN must be hashed before storage';
    END IF;
  END IF;
  
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF NEW.is_data_encrypted = false AND (NEW.iban !~ '^\*+' OR NEW.bic !~ '^\*+') THEN
      RAISE EXCEPTION 'Security violation: IBAN/BIC must be masked or encrypted';
    END IF;
  END IF;
  
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
      RAISE EXCEPTION 'Security violation: GitHub access tokens must be encrypted';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_user_profile_data ON public.user_profiles;
CREATE TRIGGER validate_user_profile_data
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.validate_sensitive_data_encryption();

DROP TRIGGER IF EXISTS validate_iban_data ON public.iban_accounts;
CREATE TRIGGER validate_iban_data
  BEFORE INSERT OR UPDATE ON public.iban_accounts
  FOR EACH ROW EXECUTE FUNCTION public.validate_sensitive_data_encryption();

DROP TRIGGER IF EXISTS validate_github_token_data ON public.github_integrations;
CREATE TRIGGER validate_github_token_data
  BEFORE INSERT OR UPDATE ON public.github_integrations
  FOR EACH ROW EXECUTE FUNCTION public.validate_sensitive_data_encryption();