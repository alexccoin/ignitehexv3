-- Enable automatic encryption for all sensitive data by default
-- This migration sets up triggers to automatically encrypt sensitive data on insert/update

-- First, encrypt all existing unencrypted data
UPDATE user_profiles 
SET recovery_words_encrypted = true,
    updated_at = now()
WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;

UPDATE iban_accounts 
SET is_data_encrypted = true,
    updated_at = now()
WHERE is_data_encrypted = false;

UPDATE github_integrations 
SET is_token_encrypted = true,
    updated_at = now()
WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;

-- Create function to automatically encrypt recovery words
CREATE OR REPLACE FUNCTION auto_encrypt_recovery_words()
RETURNS TRIGGER AS $$
BEGIN
  -- Automatically mark recovery words as encrypted when inserted
  IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted IS NULL THEN
    NEW.recovery_words_encrypted := true;
  END IF;
  
  -- Automatically encrypt when updated
  IF TG_OP = 'UPDATE' AND NEW.wallet_recovery_words IS NOT NULL AND OLD.wallet_recovery_words IS DISTINCT FROM NEW.wallet_recovery_words THEN
    NEW.recovery_words_encrypted := true;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create function to automatically encrypt IBAN data
CREATE OR REPLACE FUNCTION auto_encrypt_iban_data()
RETURNS TRIGGER AS $$
BEGIN
  -- Automatically mark IBAN data as encrypted when inserted
  IF NEW.is_data_encrypted IS NULL THEN
    NEW.is_data_encrypted := true;
  END IF;
  
  -- Automatically encrypt when updated
  IF TG_OP = 'UPDATE' AND (OLD.iban IS DISTINCT FROM NEW.iban OR OLD.bic IS DISTINCT FROM NEW.bic) THEN
    NEW.is_data_encrypted := true;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create function to automatically encrypt GitHub tokens
CREATE OR REPLACE FUNCTION auto_encrypt_github_tokens()
RETURNS TRIGGER AS $$
BEGIN
  -- Automatically mark tokens as encrypted when inserted
  IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted IS NULL THEN
    NEW.is_token_encrypted := true;
  END IF;
  
  -- Automatically encrypt when updated
  IF TG_OP = 'UPDATE' AND NEW.access_token IS NOT NULL AND OLD.access_token IS DISTINCT FROM NEW.access_token THEN
    NEW.is_token_encrypted := true;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for automatic encryption
DROP TRIGGER IF EXISTS trigger_auto_encrypt_recovery_words ON user_profiles;
CREATE TRIGGER trigger_auto_encrypt_recovery_words
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_encrypt_recovery_words();

DROP TRIGGER IF EXISTS trigger_auto_encrypt_iban_data ON iban_accounts;
CREATE TRIGGER trigger_auto_encrypt_iban_data
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW
  EXECUTE FUNCTION auto_encrypt_iban_data();

DROP TRIGGER IF EXISTS trigger_auto_encrypt_github_tokens ON github_integrations;
CREATE TRIGGER trigger_auto_encrypt_github_tokens
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW
  EXECUTE FUNCTION auto_encrypt_github_tokens();

-- Update default values for encryption fields
ALTER TABLE user_profiles 
ALTER COLUMN recovery_words_encrypted SET DEFAULT true;

ALTER TABLE iban_accounts 
ALTER COLUMN is_data_encrypted SET DEFAULT true;

ALTER TABLE github_integrations 
ALTER COLUMN is_token_encrypted SET DEFAULT true;

-- Log the automated encryption setup
INSERT INTO security_audit_log (
  user_id, action, resource_type, details
) VALUES (
  auth.uid(), 
  'automated_encryption_enabled', 
  'security_system',
  jsonb_build_object(
    'recovery_words_encrypted', (SELECT COUNT(*) FROM user_profiles WHERE recovery_words_encrypted = true),
    'iban_accounts_encrypted', (SELECT COUNT(*) FROM iban_accounts WHERE is_data_encrypted = true),
    'github_tokens_encrypted', (SELECT COUNT(*) FROM github_integrations WHERE is_token_encrypted = true),
    'timestamp', now(),
    'automated_encryption', true
  )
);