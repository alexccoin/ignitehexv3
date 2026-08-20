-- Drop and recreate triggers to ensure they're only on the correct tables
-- First, drop any existing validation triggers that might be on wrong tables

DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON user_profiles;
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON user_profiles;
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON github_integrations;
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON github_integrations;
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON iban_accounts;

-- Now ensure triggers are only on the correct tables

-- IBAN validation trigger only on iban_accounts table
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON iban_accounts;
CREATE TRIGGER validate_iban_encryption_trigger
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION validate_iban_encryption();

-- GitHub token validation trigger only on github_integrations table  
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON github_integrations;
CREATE TRIGGER validate_github_token_security_trigger
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION validate_github_token_security();

-- Recovery words validation trigger only on user_profiles table
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON user_profiles;
CREATE TRIGGER validate_recovery_words_encryption_trigger
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION validate_recovery_words_encryption();

-- Create a simpler version of the IBAN validation that doesn't cause field access issues
CREATE OR REPLACE FUNCTION public.validate_iban_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- This trigger should only be on iban_accounts table
  -- Ensure IBAN/BIC data is encrypted when is_data_encrypted is true
  IF NEW.is_data_encrypted = true THEN
    -- If marked as encrypted, ensure encrypted fields are populated
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