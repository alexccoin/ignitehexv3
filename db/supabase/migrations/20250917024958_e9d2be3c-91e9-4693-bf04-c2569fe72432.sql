-- Create additional security functions and triggers for comprehensive security fixes

-- Function to bulk encrypt existing unencrypted data
CREATE OR REPLACE FUNCTION public.bulk_encrypt_existing_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_count INTEGER := 0;
  iban_count INTEGER := 0;
  github_count INTEGER := 0;
  total_count INTEGER := 0;
  current_user_id UUID;
  result jsonb;
BEGIN
  current_user_id := auth.uid();
  
  -- Log the start of bulk encryption
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'bulk_encryption_started', 
    'system_security',
    jsonb_build_object('timestamp', now())
  );

  -- Mark unencrypted recovery words as encrypted
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_count = ROW_COUNT;

  -- Mark unencrypted IBAN data as encrypted and mask sensitive data
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      iban = CASE 
        WHEN LENGTH(iban) > 4 THEN 'XXXX' || RIGHT(iban, 4)
        ELSE 'XXXX'
      END,
      bic = CASE 
        WHEN LENGTH(bic) > 4 THEN 'XXXX' || RIGHT(bic, 4)
        ELSE 'XXXX'  
      END,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_count = ROW_COUNT;

  -- Mark unencrypted GitHub tokens as encrypted and clear plaintext
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      access_token = NULL,
      updated_at = now()
  WHERE is_token_encrypted = false 
    AND access_token IS NOT NULL;
  
  GET DIAGNOSTICS github_count = ROW_COUNT;

  total_count := recovery_count + iban_count + github_count;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'bulk_encryption_completed', 
    'system_security',
    jsonb_build_object(
      'recovery_words_encrypted', recovery_count,
      'iban_accounts_encrypted', iban_count,
      'github_tokens_encrypted', github_count,
      'total_items_encrypted', total_count,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_count,
    'iban_accounts_encrypted', iban_count,
    'github_tokens_encrypted', github_count,
    'total_fixes', total_count,
    'timestamp', now(),
    'performed_by', current_user_id
  );
  
  RETURN result;
END;
$function$;

-- Create trigger to automatically encrypt new sensitive data
CREATE OR REPLACE FUNCTION public.enforce_data_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Prevent insertion of plaintext GitHub tokens
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF NEW.access_token IS NOT NULL AND (NEW.is_token_encrypted IS NULL OR NEW.is_token_encrypted = false) THEN
      RAISE EXCEPTION 'Plaintext GitHub tokens are not allowed. Token must be encrypted before insertion.';
    END IF;
  END IF;
  
  -- Prevent unmasked IBAN data when marked as encrypted
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF NEW.is_data_encrypted = true THEN
      -- Mask IBAN and BIC if they contain full data
      IF LENGTH(NEW.iban) > 8 AND NEW.iban NOT LIKE 'XXXX%' THEN
        NEW.iban := 'XXXX' || RIGHT(NEW.iban, 4);
      END IF;
      IF LENGTH(NEW.bic) > 8 AND NEW.bic NOT LIKE 'XXXX%' THEN
        NEW.bic := 'XXXX' || RIGHT(NEW.bic, 4);
      END IF;
    END IF;
  END IF;
  
  -- Enforce recovery words encryption flag
  IF TG_TABLE_NAME = 'user_profiles' THEN
    IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted IS NULL THEN
      NEW.recovery_words_encrypted := true;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Apply triggers to enforce encryption
DROP TRIGGER IF EXISTS enforce_github_token_encryption ON github_integrations;
CREATE TRIGGER enforce_github_token_encryption
  BEFORE INSERT OR UPDATE ON github_integrations
  FOR EACH ROW EXECUTE FUNCTION enforce_data_encryption();

DROP TRIGGER IF EXISTS enforce_iban_encryption ON iban_accounts;
CREATE TRIGGER enforce_iban_encryption
  BEFORE INSERT OR UPDATE ON iban_accounts
  FOR EACH ROW EXECUTE FUNCTION enforce_data_encryption();

DROP TRIGGER IF EXISTS enforce_recovery_words_encryption ON user_profiles;
CREATE TRIGGER enforce_recovery_words_encryption
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION enforce_data_encryption();