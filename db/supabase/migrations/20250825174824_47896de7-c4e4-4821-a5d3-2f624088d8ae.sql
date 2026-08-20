-- Check current triggers and fix any that might be accessing wrong fields
-- Drop and recreate all validation triggers with proper field checks

-- First, completely remove all validation triggers
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON iban_accounts CASCADE;
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON github_integrations CASCADE;
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON user_profiles CASCADE;

-- Drop functions (this should work now since triggers are dropped)
DROP FUNCTION IF EXISTS validate_iban_encryption() CASCADE;
DROP FUNCTION IF EXISTS validate_github_token_security() CASCADE; 
DROP FUNCTION IF EXISTS validate_recovery_words_encryption() CASCADE;

-- Create IBAN validation function - ONLY accesses iban_accounts fields
CREATE OR REPLACE FUNCTION public.validate_iban_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- This function should ONLY be used on iban_accounts table
  -- iban_accounts has: is_data_encrypted, encrypted_iban, encrypted_bic, iban, bic
  
  IF TG_TABLE_NAME != 'iban_accounts' THEN
    RAISE EXCEPTION 'validate_iban_encryption can only be used on iban_accounts table';
  END IF;
  
  -- Check if data should be encrypted
  IF NEW.is_data_encrypted = true THEN
    IF NEW.encrypted_iban IS NULL OR NEW.encrypted_bic IS NULL THEN
      RAISE EXCEPTION 'Encrypted IBAN and BIC fields must be populated when is_data_encrypted is true.';
    END IF;
    
    -- Mask plaintext fields when encrypted
    IF NEW.iban IS NOT NULL AND length(NEW.iban) > 8 THEN
      NEW.iban := left(NEW.iban, 4) || repeat('*', length(NEW.iban) - 8) || right(NEW.iban, 4);
    END IF;
    IF NEW.bic IS NOT NULL AND length(NEW.bic) > 6 THEN
      NEW.bic := left(NEW.bic, 3) || repeat('*', length(NEW.bic) - 6) || right(NEW.bic, 3);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Create GitHub token validation function - ONLY accesses github_integrations fields  
CREATE OR REPLACE FUNCTION public.validate_github_token_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- This function should ONLY be used on github_integrations table
  -- github_integrations has: is_token_encrypted, encrypted_access_token, access_token
  
  IF TG_TABLE_NAME != 'github_integrations' THEN
    RAISE EXCEPTION 'validate_github_token_security can only be used on github_integrations table';
  END IF;
  
  -- Check if token should be encrypted
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

-- Create recovery words validation function - ONLY accesses user_profiles fields
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- This function should ONLY be used on user_profiles table
  -- user_profiles has: recovery_words_encrypted, wallet_recovery_words, recovery_words_iv
  
  IF TG_TABLE_NAME != 'user_profiles' THEN
    RAISE EXCEPTION 'validate_recovery_words_encryption can only be used on user_profiles table';
  END IF;
  
  -- Allow encryption workflows, just manage the transition
  IF NEW.recovery_words_encrypted = true AND (OLD IS NULL OR OLD.recovery_words_encrypted = false) THEN
    -- This is an encryption operation - clear plaintext recovery words for security
    NEW.wallet_recovery_words := NULL;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Create triggers only on their specific tables
CREATE TRIGGER validate_iban_encryption_trigger
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION validate_iban_encryption();

CREATE TRIGGER validate_github_token_security_trigger  
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION validate_github_token_security();

CREATE TRIGGER validate_recovery_words_encryption_trigger
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION validate_recovery_words_encryption();