-- Fix validation triggers to use correct field names for each table

-- Drop all existing validation triggers and functions
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON github_integrations;
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON user_profiles;
DROP FUNCTION IF EXISTS validate_iban_encryption();
DROP FUNCTION IF EXISTS validate_github_token_security();
DROP FUNCTION IF EXISTS validate_recovery_words_encryption();

-- Create IBAN validation function (uses is_data_encrypted field)
CREATE OR REPLACE FUNCTION public.validate_iban_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only for iban_accounts table - check is_data_encrypted field
  IF NEW.is_data_encrypted = true THEN
    IF NEW.encrypted_iban IS NULL OR NEW.encrypted_bic IS NULL THEN
      RAISE EXCEPTION 'Encrypted IBAN and BIC fields must be populated when is_data_encrypted is true.';
    END IF;
    
    -- Mask plaintext fields when encrypted
    IF length(NEW.iban) > 8 THEN
      NEW.iban := left(NEW.iban, 4) || repeat('*', length(NEW.iban) - 8) || right(NEW.iban, 4);
    END IF;
    IF length(NEW.bic) > 6 THEN
      NEW.bic := left(NEW.bic, 3) || repeat('*', length(NEW.bic) - 6) || right(NEW.bic, 3);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Create GitHub token validation function (uses is_token_encrypted field)
CREATE OR REPLACE FUNCTION public.validate_github_token_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only for github_integrations table - check is_token_encrypted field
  IF NEW.is_token_encrypted = true THEN
    IF NEW.encrypted_access_token IS NULL THEN
      RAISE EXCEPTION 'Encrypted access token must be populated when is_token_encrypted is true.';
    END IF;
    
    -- Clear plaintext token when encrypted
    NEW.access_token := NULL;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Create recovery words validation function (uses recovery_words_encrypted field)
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only for user_profiles table - check recovery_words_encrypted field
  IF NEW.recovery_words_encrypted = true THEN
    IF NEW.wallet_recovery_words IS NOT NULL AND array_length(NEW.wallet_recovery_words, 1) IS NOT NULL THEN
      RAISE EXCEPTION 'Recovery words must be encrypted when recovery_words_encrypted is true.';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Create triggers only on correct tables
CREATE TRIGGER validate_iban_encryption_trigger
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION validate_iban_encryption();

CREATE TRIGGER validate_github_token_security_trigger
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION validate_github_token_security();

CREATE TRIGGER validate_recovery_words_encryption_trigger
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION validate_recovery_words_encryption();