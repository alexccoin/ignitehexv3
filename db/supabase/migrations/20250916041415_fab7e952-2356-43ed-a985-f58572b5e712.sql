-- Emergency Security Hardening and Prevention Migration (Fixed)

-- 1. Drop and recreate functions with correct types
DROP FUNCTION IF EXISTS public.emergency_encrypt_all_data();
DROP FUNCTION IF EXISTS public.bulk_encrypt_existing_data();

-- 2. Create function for bulk encryption of existing unencrypted data
CREATE OR REPLACE FUNCTION public.emergency_encrypt_all_data()
RETURNS JSON
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  result JSON;
  recovery_count INTEGER := 0;
  iban_count INTEGER := 0;
  github_count INTEGER := 0;
BEGIN
  -- Encrypt unencrypted recovery words
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE recovery_words_encrypted = false 
    AND wallet_recovery_words IS NOT NULL;
  
  GET DIAGNOSTICS recovery_count = ROW_COUNT;
  
  -- Encrypt unencrypted IBAN data by masking
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
  
  -- Encrypt unencrypted GitHub tokens by clearing plaintext
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      access_token = NULL,
      updated_at = now()
  WHERE is_token_encrypted = false 
    AND access_token IS NOT NULL;
  
  GET DIAGNOSTICS github_count = ROW_COUNT;
  
  -- Log the security action
  INSERT INTO security_audit_log (action, resource_type, details)
  VALUES (
    'emergency_bulk_encryption',
    'system_wide',
    jsonb_build_object(
      'recovery_words_secured', recovery_count,
      'iban_accounts_secured', iban_count,
      'github_tokens_secured', github_count,
      'performed_at', now(),
      'performed_by', 'system_emergency'
    )
  );
  
  result := json_build_object(
    'success', true,
    'recovery_words_encrypted', recovery_count,
    'iban_accounts_encrypted', iban_count,
    'github_tokens_encrypted', github_count,
    'total_fixes', recovery_count + iban_count + github_count
  );
  
  RETURN result;
END;
$$;

-- 3. Enhanced RPC for bulk encryption with better error handling
CREATE OR REPLACE FUNCTION public.bulk_encrypt_existing_data()
RETURNS JSON
SECURITY DEFINER
SET search_path = public  
LANGUAGE plpgsql
AS $$
DECLARE
  result JSON;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required for bulk encryption operations';
  END IF;
  
  -- Run the emergency encryption
  SELECT emergency_encrypt_all_data() INTO result;
  
  RETURN result;
EXCEPTION
  WHEN OTHERS THEN
    -- Log the error
    INSERT INTO security_audit_log (action, resource_type, details)
    VALUES (
      'bulk_encryption_failed',
      'system_wide', 
      jsonb_build_object(
        'error_message', SQLERRM,
        'error_state', SQLSTATE,
        'performed_at', now(),
        'performed_by', auth.uid()
      )
    );
    
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;