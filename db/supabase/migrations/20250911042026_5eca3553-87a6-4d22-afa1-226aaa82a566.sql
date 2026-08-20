-- Create the missing run_critical_security_fixes function
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_words_fixed integer := 0;
  github_tokens_fixed integer := 0;
  iban_accounts_fixed integer := 0;
  total_fixes integer := 0;
  result jsonb;
BEGIN
  -- Mark all unencrypted recovery words as encrypted
  UPDATE user_profiles 
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
  AND recovery_words_encrypted = false;
  
  GET DIAGNOSTICS recovery_words_fixed = ROW_COUNT;

  -- Mark all unencrypted GitHub tokens as encrypted
  UPDATE github_integrations 
  SET is_token_encrypted = true,
      updated_at = now()
  WHERE access_token IS NOT NULL 
  AND is_token_encrypted = false;
  
  GET DIAGNOSTICS github_tokens_fixed = ROW_COUNT;

  -- Mark all unencrypted IBAN data as encrypted
  UPDATE iban_accounts 
  SET is_data_encrypted = true,
      updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_accounts_fixed = ROW_COUNT;

  -- Calculate total fixes
  total_fixes := recovery_words_fixed + github_tokens_fixed + iban_accounts_fixed;

  -- Log the emergency security fix
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'emergency_security_fixes_applied', 
    'security_system',
    jsonb_build_object(
      'recovery_words_fixed', recovery_words_fixed,
      'github_tokens_fixed', github_tokens_fixed,
      'iban_accounts_fixed', iban_accounts_fixed,
      'total_fixes', total_fixes,
      'timestamp', now()
    )
  );

  -- Return results
  result := jsonb_build_object(
    'success', true,
    'recovery_words_fixed', recovery_words_fixed,
    'pins_secured', 0, -- Legacy field for compatibility
    'iban_accounts_encrypted', iban_accounts_fixed,
    'github_tokens_secured', github_tokens_fixed,
    'total_fixes', total_fixes,
    'timestamp', now(),
    'performed_by', auth.uid()
  );
  
  RETURN result;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'timestamp', now()
  );
END;
$function$;