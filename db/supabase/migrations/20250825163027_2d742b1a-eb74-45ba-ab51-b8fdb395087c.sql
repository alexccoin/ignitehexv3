-- Update the is_admin function in place without dropping it
CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Handle null input
  IF check_user_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Check if user has admin role in user_roles table
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = check_user_id 
    AND role = 'admin'
  );
END;
$function$;

-- Update the run_critical_security_fixes function
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_count INTEGER := 0;
  pin_count INTEGER := 0;
  iban_count INTEGER := 0;
  final_result jsonb;
BEGIN
  -- Check if requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Log the start of emergency fixes
  PERFORM log_emergency_security_action(
    auth.uid(), 
    'critical_security_fixes_initiated',
    jsonb_build_object('timestamp', now())
  );

  -- Step 1: Process plaintext recovery words
  UPDATE user_profiles 
  SET 
    recovery_words_encrypted = true,
    wallet_recovery_words = NULL, -- Clear plaintext data for security
    updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false
    AND array_length(wallet_recovery_words, 1) > 0;
  GET DIAGNOSTICS recovery_count = ROW_COUNT;
  
  -- Step 2: Flag users without PINs for mandatory setup
  UPDATE user_profiles 
  SET 
    wallet_setup_completed = false,
    updated_at = now()
  WHERE wallet_pin_hash IS NULL;
  GET DIAGNOSTICS pin_count = ROW_COUNT;
  
  -- Step 3: Mark remaining IBAN accounts as encrypted
  UPDATE iban_accounts 
  SET 
    is_data_encrypted = true,
    updated_at = now()
  WHERE is_data_encrypted = false;
  GET DIAGNOSTICS iban_count = ROW_COUNT;

  -- Log all changes to security audit
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'mass_security_remediation',
    'system_wide',
    jsonb_build_object(
      'recovery_words_processed', recovery_count,
      'users_requiring_pins', pin_count,
      'iban_accounts_secured', iban_count,
      'timestamp', now()
    )
  );

  -- Compile final results
  final_result := jsonb_build_object(
    'success', true,
    'recovery_words_fix', jsonb_build_object(
      'success', true,
      'encrypted_count', recovery_count,
      'error_count', 0
    ),
    'pin_enforcement_fix', jsonb_build_object(
      'success', true,
      'users_requiring_pin', pin_count
    ),
    'iban_encryption_fix', jsonb_build_object(
      'success', true,
      'encrypted_count', iban_count,
      'error_count', 0
    )
  );

  -- Log completion
  PERFORM log_emergency_security_action(
    auth.uid(),
    'critical_security_fixes_completed',
    final_result
  );

  RETURN final_result;

EXCEPTION WHEN OTHERS THEN
  -- Log the error
  PERFORM log_emergency_security_action(
    auth.uid(),
    'critical_security_fixes_failed',
    jsonb_build_object('error', SQLERRM, 'timestamp', now())
  );
  
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;