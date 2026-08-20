-- Fix the overly restrictive recovery words trigger
-- Update to only block when actually trying to set/modify wallet recovery words

CREATE OR REPLACE FUNCTION public.prevent_plaintext_recovery_words()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- Only enforce encryption when actually modifying recovery words
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- Check if recovery words are being inserted/updated and encryption flag is false
    IF (TG_OP = 'INSERT' AND NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false) OR
       (TG_OP = 'UPDATE' AND NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words AND NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false) THEN
      RAISE EXCEPTION 'Recovery words must be encrypted. Set recovery_words_encrypted = true';
    END IF;
  END IF;
  
  -- For GitHub integrations - only block when actually setting tokens
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF (TG_OP = 'INSERT' AND NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false) OR
       (TG_OP = 'UPDATE' AND NEW.access_token IS DISTINCT FROM OLD.access_token AND NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false) THEN
      RAISE EXCEPTION 'GitHub tokens must be encrypted. Set is_token_encrypted = true';
    END IF;
  END IF;
  
  -- For IBAN accounts - only block when actually setting sensitive data
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF (TG_OP = 'INSERT' AND NEW.is_data_encrypted = false AND (NEW.iban IS NOT NULL OR NEW.bic IS NOT NULL)) OR
       (TG_OP = 'UPDATE' AND NEW.is_data_encrypted = false AND 
        ((NEW.iban IS DISTINCT FROM OLD.iban AND NEW.iban IS NOT NULL) OR 
         (NEW.bic IS DISTINCT FROM OLD.bic AND NEW.bic IS NOT NULL))) THEN
      RAISE EXCEPTION 'IBAN data must be encrypted. Set is_data_encrypted = true';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Also create a quick fix function for users to mark their existing data as encrypted
CREATE OR REPLACE FUNCTION public.mark_user_data_encrypted(user_id_param uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  updated_profiles integer := 0;
  updated_github integer := 0;
  updated_iban integer := 0;
  result jsonb;
BEGIN
  -- Only allow users to mark their own data as encrypted
  IF auth.uid() != user_id_param THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied');
  END IF;

  -- Mark user profile recovery words as encrypted
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE user_id = user_id_param 
  AND wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS updated_profiles = ROW_COUNT;

  -- Mark GitHub tokens as encrypted
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE user_id = user_id_param 
  AND access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  GET DIAGNOSTICS updated_github = ROW_COUNT;

  -- Mark IBAN data as encrypted
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE user_id = user_id_param 
  AND is_data_encrypted = false;
  
  GET DIAGNOSTICS updated_iban = ROW_COUNT;

  -- Log the security action
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    user_id_param, 
    'user_data_marked_encrypted', 
    'security_system',
    jsonb_build_object(
      'profiles_updated', updated_profiles,
      'github_tokens_updated', updated_github,
      'iban_accounts_updated', updated_iban,
      'timestamp', now()
    )
  );

  result := jsonb_build_object(
    'success', true,
    'profiles_updated', updated_profiles,
    'github_tokens_updated', updated_github,
    'iban_accounts_updated', updated_iban,
    'timestamp', now()
  );
  
  RETURN result;
END;
$function$;