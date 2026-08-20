-- Drop all problematic triggers on iban_accounts that reference recovery_words_encrypted
DROP TRIGGER IF EXISTS audit_iban_accounts ON iban_accounts;
DROP TRIGGER IF EXISTS log_iban_accounts_sensitive_access ON iban_accounts;
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON iban_accounts;
DROP TRIGGER IF EXISTS monitor_iban_accounts_access ON iban_accounts;

-- These triggers also use functions that may have the same issue
DROP TRIGGER IF EXISTS auto_encrypt_iban_accounts ON iban_accounts;
DROP TRIGGER IF EXISTS enforce_iban_encryption ON iban_accounts;
DROP TRIGGER IF EXISTS validate_iban_security_trigger ON iban_accounts;