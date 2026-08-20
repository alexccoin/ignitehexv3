-- Fix security warnings by setting proper search_path for new functions

-- Fix validate_user_profile_security function
CREATE OR REPLACE FUNCTION validate_user_profile_security()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER 
SET search_path = 'public'
AS $$
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
$$;

-- Fix validate_iban_security function
CREATE OR REPLACE FUNCTION validate_iban_security()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER 
SET search_path = 'public'
AS $$
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
$$;

-- Fix validate_github_integration_security function
CREATE OR REPLACE FUNCTION validate_github_integration_security()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER 
SET search_path = 'public'
AS $$
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
$$;

-- Fix log_security_violation function
CREATE OR REPLACE FUNCTION log_security_violation(
  violation_type TEXT,
  resource_table TEXT,
  user_id_param UUID DEFAULT NULL,
  details_param JSONB DEFAULT NULL
)
RETURNS VOID 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = 'public'
AS $$
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
$$;