-- 1) Harden RLS policies: replace profiles.role checks with is_admin(auth.uid())
-- Wallet pools admin policies
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'wallet_pools' AND policyname = 'Only admin users can modify wallet pools'
  ) THEN
    DROP POLICY "Only admin users can modify wallet pools" ON public.wallet_pools;
  END IF;
  CREATE POLICY "Only admin users can modify wallet pools"
  ON public.wallet_pools
  FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));
END $$;

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'wallet_pools' AND policyname = 'Admins can view all wallet pools'
  ) THEN
    DROP POLICY "Admins can view all wallet pools" ON public.wallet_pools;
  END IF;
  CREATE POLICY "Admins can view all wallet pools"
  ON public.wallet_pools
  FOR SELECT
  USING (is_admin(auth.uid()));
END $$;

-- Pool access admin manage policy
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'pool_access' AND policyname = 'Admin users can manage access'
  ) THEN
    DROP POLICY "Admin users can manage access" ON public.pool_access;
  END IF;
  CREATE POLICY "Admin users can manage access"
  ON public.pool_access
  FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));
END $$;

-- Transactions admin policy
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'transactions' AND policyname = 'Admin users can view all transactions'
  ) THEN
    DROP POLICY "Admin users can view all transactions" ON public.transactions;
  END IF;
  CREATE POLICY "Admin users can view all transactions"
  ON public.transactions
  FOR SELECT
  USING (is_admin(auth.uid()));
END $$;

-- 2) Enforce GitHub token encryption
CREATE OR REPLACE FUNCTION public.enforce_github_token_encryption()
RETURNS trigger AS $$
BEGIN
  IF NEW.access_token IS NOT NULL THEN
    RAISE EXCEPTION 'Plaintext GitHub access_token is not allowed. Use encrypted_access_token with is_token_encrypted=true.';
  END IF;
  IF (NEW.encrypted_access_token IS NULL) OR (COALESCE(NEW.is_token_encrypted, false) = false) THEN
    RAISE EXCEPTION 'Encrypted token and is_token_encrypted=true are required.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'tr_enforce_github_token_encryption'
  ) THEN
    DROP TRIGGER tr_enforce_github_token_encryption ON public.github_integrations;
  END IF;
  CREATE TRIGGER tr_enforce_github_token_encryption
  BEFORE INSERT OR UPDATE ON public.github_integrations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_github_token_encryption();
END $$;

-- 3) Strengthen IBAN/BIC enforcement
CREATE OR REPLACE FUNCTION public.validate_iban_security()
RETURNS trigger AS $$
BEGIN
  -- Encrypted fields require is_data_encrypted = true
  IF (NEW.encrypted_iban IS NOT NULL OR NEW.encrypted_bic IS NOT NULL) 
     AND COALESCE(NEW.is_data_encrypted, false) = false THEN
    RAISE EXCEPTION 'IBAN data must be marked as encrypted when encrypted fields are populated';
  END IF;

  -- When encrypted, force masking of plaintext columns
  IF COALESCE(NEW.is_data_encrypted, false) = true THEN
    IF NEW.iban IS NULL OR NEW.bic IS NULL THEN
      RAISE EXCEPTION 'Masked IBAN/BIC placeholders are required when data is encrypted';
    END IF;
    IF NEW.iban <> '***ENCRYPTED***' OR NEW.bic <> '***ENCRYPTED***' THEN
      RAISE EXCEPTION 'When encrypted, IBAN and BIC must be set to ***ENCRYPTED***';
    END IF;
  ELSE
    -- Basic format checks only when not encrypted/masked
    IF NEW.iban IS NOT NULL AND NEW.iban <> '***ENCRYPTED***' THEN
      IF length(NEW.iban) < 15 OR length(NEW.iban) > 34 THEN
        RAISE EXCEPTION 'Invalid IBAN format';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- Ensure trigger exists
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'tr_validate_iban_security'
  ) THEN
    CREATE TRIGGER tr_validate_iban_security
    BEFORE INSERT OR UPDATE ON public.iban_accounts
    FOR EACH ROW EXECUTE FUNCTION public.validate_iban_security();
  END IF;
END $$;

-- 4) Enforce wallet recovery words encryption shape when flagged
CREATE OR REPLACE FUNCTION public.enforce_recovery_words_encryption()
RETURNS trigger AS $$
DECLARE
  enc_val text;
BEGIN
  IF COALESCE(NEW.recovery_words_encrypted, false) = true THEN
    IF NEW.wallet_recovery_words IS NULL OR cardinality(NEW.wallet_recovery_words) <> 1 THEN
      RAISE EXCEPTION 'When recovery_words_encrypted=true, wallet_recovery_words must contain a single encrypted payload';
    END IF;
    enc_val := NEW.wallet_recovery_words[1];
    -- Require at least two ':' separators (salt:iv:cipher)
    IF (length(enc_val) - length(replace(enc_val, ':', ''))) < 2 THEN
      RAISE EXCEPTION 'Encrypted payload must follow salt:iv:ciphertext structure';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'tr_enforce_recovery_words_encryption'
  ) THEN
    DROP TRIGGER tr_enforce_recovery_words_encryption ON public.user_profiles;
  END IF;
  CREATE TRIGGER tr_enforce_recovery_words_encryption
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_recovery_words_encryption();
END $$;

-- 5) Use server-derived IP in PIN validation for recovery access
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(
  user_uuid uuid,
  input_pin text DEFAULT NULL,
  client_ip inet DEFAULT NULL
)
RETURNS jsonb AS $$
DECLARE
  recovery_words TEXT[];
  pin_validation_result jsonb;
  is_admin_user boolean;
  actual_client_ip inet;
BEGIN
  -- Check if user is admin
  SELECT is_admin(auth.uid()) INTO is_admin_user;

  IF is_admin_user THEN
    INSERT INTO public.security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      auth.uid(), 
      'admin_recovery_access', 
      'wallet_recovery',
      user_uuid::text,
      jsonb_build_object('target_user', user_uuid, 'admin_override', true)
    );

    SELECT wallet_recovery_words INTO recovery_words
    FROM public.user_profiles
    WHERE user_id = user_uuid;

    RETURN jsonb_build_object(
      'success', true,
      'recovery_words', recovery_words,
      'access_method', 'admin_override'
    );
  END IF;

  -- For regular users, validate PIN with rate limiting using server-derived IP
  IF input_pin IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'pin_required',
      'message', 'PIN is required to access recovery words.'
    );
  END IF;

  actual_client_ip := get_client_ip();
  SELECT validate_wallet_pin_secure_fixed(user_uuid, input_pin, actual_client_ip) 
  INTO pin_validation_result;

  IF NOT (pin_validation_result->>'success')::boolean THEN
    RETURN pin_validation_result;
  END IF;

  SELECT wallet_recovery_words INTO recovery_words
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (
    user_uuid, 
    'recovery_words_accessed', 
    'wallet_recovery',
    jsonb_build_object('access_method', 'pin_validation', 'ip_address', actual_client_ip::text)
  );

  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', recovery_words,
    'access_method', 'pin_validation'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- 6) Remove fallback secrets in validators
CREATE OR REPLACE FUNCTION public.validate_master_password_secure(input_password text, client_ip inet DEFAULT NULL::inet)
RETURNS jsonb AS $$
DECLARE
  valid_password text;
  rate_limit_result jsonb;
  actual_ip inet;
BEGIN
  actual_ip := COALESCE(client_ip, get_client_ip());
  SELECT check_rate_limit_with_progressive_delay(NULL, actual_ip, 'master_password', 3, 60)
  INTO rate_limit_result;
  IF NOT (rate_limit_result->>'allowed')::boolean THEN
    INSERT INTO public.auth_attempts (ip_address, attempt_type, success, additional_data)
    VALUES (actual_ip, 'master_password', false, rate_limit_result);
    RETURN jsonb_build_object(
      'success', false,
      'error', rate_limit_result->>'reason',
      'message', CASE 
        WHEN rate_limit_result->>'reason' = 'rate_limited' THEN 'Too many failed attempts. Please try again later.'
        WHEN rate_limit_result->>'reason' = 'progressive_delay' THEN 'Please wait ' || (rate_limit_result->>'retry_after') || ' seconds before trying again.'
        ELSE 'Rate limit exceeded.'
      END,
      'retry_after', rate_limit_result->>'retry_after'
    );
  END IF;

  valid_password := current_setting('app.master_password', true);
  IF valid_password IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'master_password_not_configured',
      'message', 'Master password is not configured.'
    );
  END IF;

  IF input_password = valid_password THEN
    INSERT INTO public.auth_attempts (ip_address, attempt_type, success)
    VALUES (actual_ip, 'master_password', true);
    INSERT INTO public.security_audit_log (action, resource_type, details)
    VALUES ('master_password_validated', 'system_access', jsonb_build_object('ip_address', actual_ip::text, 'timestamp', now()));
    RETURN jsonb_build_object('success', true, 'message', 'Master password validated successfully.');
  ELSE
    INSERT INTO public.auth_attempts (ip_address, attempt_type, success)
    VALUES (actual_ip, 'master_password', false);
    INSERT INTO public.security_audit_log (action, resource_type, details)
    VALUES ('master_password_failed', 'system_access', jsonb_build_object('ip_address', actual_ip::text, 'timestamp', now()));
    RETURN jsonb_build_object('success', false, 'error', 'invalid_password', 'message', 'Invalid master password.');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

CREATE OR REPLACE FUNCTION public.validate_founder_access_code(access_code text)
RETURNS boolean AS $$
DECLARE
  valid_code text;
BEGIN
  valid_code := current_setting('app.founder_access_code', true);
  IF valid_code IS NULL THEN
    RETURN false;
  END IF;
  RETURN access_code = valid_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';