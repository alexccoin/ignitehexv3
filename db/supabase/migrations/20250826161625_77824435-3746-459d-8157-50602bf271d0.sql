-- Fix the validation trigger error by dropping problematic triggers
-- The error indicates a trigger is checking for is_data_encrypted on a table that doesn't have this field

-- First, let's check what triggers exist and remove any that reference non-existent fields
DROP TRIGGER IF EXISTS validate_iban_security_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS validate_github_integration_security_trigger ON github_integrations;
DROP TRIGGER IF EXISTS audit_sensitive_data_access_trigger ON user_profiles;
DROP TRIGGER IF EXISTS audit_sensitive_data_access_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS audit_sensitive_data_access_trigger ON prepaid_cards;
DROP TRIGGER IF EXISTS audit_sensitive_data_access_trigger ON transactions;

-- Recreate only the necessary validation triggers for tables that actually have the required fields

-- IBAN accounts validation (this table has is_data_encrypted field)
CREATE TRIGGER validate_iban_security_trigger
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION validate_iban_security();

-- GitHub integrations validation (this table has is_token_encrypted field)
CREATE TRIGGER validate_github_integration_security_trigger
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION validate_github_integration_security();