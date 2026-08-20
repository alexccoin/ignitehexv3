-- Fix validation triggers to only check fields being actively modified
-- This prevents blocking legitimate profile updates due to pre-existing unencrypted data

CREATE OR REPLACE FUNCTION public.validate_sensitive_data_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- Only validate wallet_recovery_words if it's being actively changed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.wallet_recovery_words IS DISTINCT FROM NEW.wallet_recovery_words) THEN
      IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
        RAISE EXCEPTION 'Security violation: Recovery words must be encrypted before storage';
      END IF;
    END IF;
    
    -- Only validate wallet_pin_hash if it's being actively changed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.wallet_pin_hash IS DISTINCT FROM NEW.wallet_pin_hash) THEN
      IF NEW.wallet_pin_hash IS NOT NULL AND NEW.wallet_pin_hash NOT LIKE '$2%' THEN
        RAISE EXCEPTION 'Security violation: Wallet PIN must be hashed before storage';
      END IF;
    END IF;
  END IF;
  
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    -- Only validate IBAN/BIC if they're being actively changed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND (OLD.iban IS DISTINCT FROM NEW.iban OR OLD.bic IS DISTINCT FROM NEW.bic)) THEN
      IF NEW.is_data_encrypted = false AND (NEW.iban !~ '^\*+' OR NEW.bic !~ '^\*+') THEN
        RAISE EXCEPTION 'Security violation: IBAN/BIC must be masked or encrypted';
      END IF;
    END IF;
  END IF;
  
  IF TG_TABLE_NAME = 'github_integrations' THEN
    -- Only validate access_token if it's being actively changed
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.access_token IS DISTINCT FROM NEW.access_token) THEN
      IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
        RAISE EXCEPTION 'Security violation: GitHub access tokens must be encrypted';
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Fix validation for user profile security to be less strict on legitimate content
CREATE OR REPLACE FUNCTION public.validate_user_profile_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Validate email format only if being changed
  IF (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.email_address IS DISTINCT FROM NEW.email_address)) THEN
    IF NEW.email_address IS NOT NULL AND NOT NEW.email_address ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
      RAISE EXCEPTION 'Invalid email format';
    END IF;
  END IF;
  
  -- Validate full name only if being changed - check for actual script injection attempts
  IF (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.full_name IS DISTINCT FROM NEW.full_name)) THEN
    IF NEW.full_name IS NOT NULL AND (
      NEW.full_name ILIKE '%<script%' OR 
      NEW.full_name ILIKE '%</script>%' OR
      NEW.full_name ILIKE '%javascript:%' OR 
      NEW.full_name ILIKE '%onerror%=%' OR
      NEW.full_name ILIKE '%onclick%=%'
    ) THEN
      RAISE EXCEPTION 'Invalid characters in full name';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;