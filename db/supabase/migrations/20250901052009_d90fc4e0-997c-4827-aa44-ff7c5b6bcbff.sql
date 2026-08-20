-- Drop the problematic trigger on user_profiles that's causing the field access error
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON user_profiles;

-- Recreate it only for tables that actually need this level of logging
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON github_integrations;

-- Create specific triggers for tables that have encryption fields
CREATE TRIGGER log_sensitive_data_access_trigger
AFTER INSERT OR UPDATE OR DELETE ON iban_accounts
FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();

CREATE TRIGGER log_sensitive_data_access_trigger
AFTER INSERT OR UPDATE OR DELETE ON github_integrations
FOR EACH ROW EXECUTE FUNCTION log_sensitive_data_access();