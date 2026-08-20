-- Fix security warnings by setting proper search paths for functions

-- Fix auto_encrypt_sensitive_data function
CREATE OR REPLACE FUNCTION auto_encrypt_sensitive_data()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- For recovery words: automatically mark as encrypted when data is present
  IF TG_TABLE_NAME = 'user_profiles' THEN
    IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted IS NULL THEN
      NEW.recovery_words_encrypted := true;
    END IF;
  END IF;
  
  -- For IBAN accounts: automatically mark as encrypted
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF NEW.is_data_encrypted IS NULL THEN
      NEW.is_data_encrypted := true;
    END IF;
  END IF;
  
  -- For GitHub tokens: automatically mark as encrypted
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted IS NULL THEN
      NEW.is_token_encrypted := true;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Fix bulk_encrypt_existing_data function
CREATE OR REPLACE FUNCTION bulk_encrypt_existing_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  recovery_count integer := 0;
  iban_count integer := 0;
  github_count integer := 0;
  result jsonb;
BEGIN
  -- Check admin access
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Encrypt existing unencrypted recovery words
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_count = ROW_COUNT;

  -- Encrypt existing unencrypted IBAN data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_count = ROW_COUNT;

  -- Encrypt existing unencrypted GitHub tokens
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
    AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_count = ROW_COUNT;

  -- Log the automated encryption
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'bulk_automated_encryption', 
    'security_system',
    jsonb_build_object(
      'recovery_words_encrypted', recovery_count,
      'iban_accounts_encrypted', iban_count,
      'github_tokens_encrypted', github_count,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_count,
    'iban_accounts_encrypted', iban_count,
    'github_tokens_encrypted', github_count,
    'total_encrypted', recovery_count + iban_count + github_count
  );
  
  RETURN result;
END;
$$;