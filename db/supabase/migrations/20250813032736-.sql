-- CRITICAL SECURITY FIXES: Enhanced RLS policies and access controls

-- 1. Fix liquidity pools table to require authentication for business data
DROP POLICY IF EXISTS "Anyone can view liquidity pools" ON public.liquidity_pools;
CREATE POLICY "Authenticated users can view liquidity pools" 
ON public.liquidity_pools 
FOR SELECT 
USING (auth.uid() IS NOT NULL);

-- 2. Enhance chat message security with better input validation
DROP POLICY IF EXISTS "Users can view public chat messages secure" ON public.chat_messages;
CREATE POLICY "Users can view public chat messages secure" 
ON public.chat_messages 
FOR SELECT 
USING (
  auth.uid() IS NOT NULL 
  AND room_type = 'public'
  AND length(message) <= 1000
  AND length(username) <= 100
  AND NOT (message ILIKE '%<script%' OR message ILIKE '%javascript:%' OR message ILIKE '%on[a-z]%=%')
);

-- 3. Add enhanced security validation for user profiles
CREATE OR REPLACE FUNCTION validate_user_profile_security()
RETURNS TRIGGER AS $$
BEGIN
  -- Validate email format
  IF NEW.email_address IS NOT NULL AND NOT NEW.email_address ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;
  
  -- Validate full name (no script tags or suspicious content)
  IF NEW.full_name IS NOT NULL AND (
    NEW.full_name ILIKE '%<script%' OR 
    NEW.full_name ILIKE '%javascript:%' OR 
    NEW.full_name ILIKE '%on[a-z]%=%'
  ) THEN
    RAISE EXCEPTION 'Invalid characters in full name';
  END IF;
  
  -- Validate recovery words encryption flag consistency
  IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
    RAISE EXCEPTION 'Recovery words must be encrypted when stored';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply validation trigger to user profiles
DROP TRIGGER IF EXISTS validate_user_profile_security_trigger ON public.user_profiles;
CREATE TRIGGER validate_user_profile_security_trigger
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION validate_user_profile_security();

-- 4. Enhanced security for IBAN accounts - ensure data is encrypted
CREATE OR REPLACE FUNCTION validate_iban_security()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure sensitive data is marked as encrypted when storing encrypted values
  IF (NEW.encrypted_iban IS NOT NULL OR NEW.encrypted_bic IS NOT NULL) 
     AND NEW.is_data_encrypted = false THEN
    RAISE EXCEPTION 'IBAN data must be marked as encrypted when encrypted fields are populated';
  END IF;
  
  -- Validate IBAN format (basic check)
  IF NEW.iban IS NOT NULL AND NEW.iban != '***ENCRYPTED***' THEN
    IF length(NEW.iban) < 15 OR length(NEW.iban) > 34 THEN
      RAISE EXCEPTION 'Invalid IBAN format';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply validation trigger to IBAN accounts
DROP TRIGGER IF EXISTS validate_iban_security_trigger ON public.iban_accounts;
CREATE TRIGGER validate_iban_security_trigger
  BEFORE INSERT OR UPDATE ON public.iban_accounts
  FOR EACH ROW EXECUTE FUNCTION validate_iban_security();

-- 5. Enhanced GitHub integration security
CREATE OR REPLACE FUNCTION validate_github_integration_security()
RETURNS TRIGGER AS $$
BEGIN
  -- Ensure tokens are encrypted when storing encrypted values
  IF NEW.encrypted_access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
    RAISE EXCEPTION 'GitHub token must be marked as encrypted when encrypted field is populated';
  END IF;
  
  -- Validate GitHub username format
  IF NEW.github_username IS NOT NULL AND (
    length(NEW.github_username) > 39 OR 
    NEW.github_username ~ '[^a-zA-Z0-9\-]'
  ) THEN
    RAISE EXCEPTION 'Invalid GitHub username format';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply validation trigger to GitHub integrations
DROP TRIGGER IF EXISTS validate_github_integration_security_trigger ON public.github_integrations;
CREATE TRIGGER validate_github_integration_security_trigger
  BEFORE INSERT OR UPDATE ON public.github_integrations
  FOR EACH ROW EXECUTE FUNCTION validate_github_integration_security();

-- 6. Add comprehensive security audit function
CREATE OR REPLACE FUNCTION log_security_violation(
  violation_type TEXT,
  resource_table TEXT,
  user_id_param UUID DEFAULT NULL,
  details_param JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    COALESCE(user_id_param, auth.uid()),
    violation_type,
    resource_table,
    COALESCE(details_param, '{}'),
    get_client_ip()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;