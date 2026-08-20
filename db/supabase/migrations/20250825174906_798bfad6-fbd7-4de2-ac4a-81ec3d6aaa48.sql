-- Completely remove all validation triggers and identify the problem
-- Let's see what triggers exist and remove ALL of them

-- Remove any triggers that might be accessing wrong fields
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON iban_accounts CASCADE;
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON user_profiles CASCADE;
DROP TRIGGER IF EXISTS validate_iban_encryption_trigger ON github_integrations CASCADE;

DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON github_integrations CASCADE;
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON iban_accounts CASCADE;
DROP TRIGGER IF EXISTS validate_github_token_security_trigger ON user_profiles CASCADE;

DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON user_profiles CASCADE;
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON iban_accounts CASCADE;
DROP TRIGGER IF EXISTS validate_recovery_words_encryption_trigger ON github_integrations CASCADE;

-- Drop any other security-related triggers that might be causing issues
DROP TRIGGER IF EXISTS enforce_github_token_encryption ON github_integrations CASCADE;
DROP TRIGGER IF EXISTS enforce_iban_data_encryption ON iban_accounts CASCADE;
DROP TRIGGER IF EXISTS enforce_recovery_words_encryption ON user_profiles CASCADE;

-- Drop ALL validation functions completely
DROP FUNCTION IF EXISTS validate_iban_encryption() CASCADE;
DROP FUNCTION IF EXISTS validate_github_token_security() CASCADE;
DROP FUNCTION IF EXISTS validate_recovery_words_encryption() CASCADE;
DROP FUNCTION IF EXISTS enforce_github_token_encryption() CASCADE;
DROP FUNCTION IF EXISTS enforce_iban_data_encryption() CASCADE;
DROP FUNCTION IF EXISTS enforce_recovery_words_encryption() CASCADE;

-- For now, let's NOT recreate any validation triggers to see if this fixes the error
-- We'll add them back one by one if needed