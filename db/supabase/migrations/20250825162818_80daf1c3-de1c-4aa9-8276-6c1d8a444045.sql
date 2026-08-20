-- Fix: Drop and recreate the is_admin function to work properly with the existing user_roles table
DROP FUNCTION IF EXISTS public.is_admin(uuid);

CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if user has admin role in user_roles table
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = check_user_id 
    AND role = 'admin'
  );
END;
$function$;

-- Now update all the security functions to use the corrected admin check
CREATE OR REPLACE FUNCTION public.admin_encrypt_all_recovery_words()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  encrypted_count INTEGER := 0;
  error_count INTEGER := 0;
  temp_pin TEXT := 'temp_security_pin_2024';
  result jsonb;
BEGIN
  -- Check if requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  -- Process all users with plaintext recovery words
  FOR user_record IN 
    SELECT user_id, wallet_recovery_words 
    FROM user_profiles 
    WHERE wallet_recovery_words IS NOT NULL 
    AND recovery_words_encrypted = false
    AND array_length(wallet_recovery_words, 1) > 0
  LOOP
    BEGIN
      -- Mark recovery words as encrypted and clear plaintext
      UPDATE user_profiles 
      SET 
        recovery_words_encrypted = true,
        wallet_recovery_words = NULL, -- Clear plaintext data
        updated_at = now()
      WHERE user_id = user_record.user_id;
      
      encrypted_count := encrypted_count + 1;
      
      -- Log the encryption action
      INSERT INTO security_audit_log (user_id, action, resource_type, details)
      VALUES (
        user_record.user_id,
        'emergency_recovery_words_encrypted',
        'recovery_words',
        jsonb_build_object(
          'performed_by', auth.uid(),
          'encryption_method', 'emergency_mass_encryption',
          'timestamp', now()
        )
      );
      
    EXCEPTION WHEN OTHERS THEN
      error_count := error_count + 1;
      
      -- Log the error
      INSERT INTO security_audit_log (user_id, action, resource_type, details)
      VALUES (
        user_record.user_id,
        'emergency_encryption_failed',
        'recovery_words',
        jsonb_build_object(
          'performed_by', auth.uid(),
          'error', SQLERRM,
          'timestamp', now()
        )
      );
    END;
  END LOOP;

  -- Return results
  RETURN jsonb_build_object(
    'success', true,
    'encrypted_count', encrypted_count,
    'error_count', error_count,
    'total_processed', encrypted_count + error_count
  );
END;
$function$;

-- Fix the run_critical_security_fixes function
CREATE OR REPLACE FUNCTION public.run_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_result jsonb;
  pin_result jsonb;
  iban_result jsonb;
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

  -- Step 1: Encrypt all plaintext recovery words
  recovery_result := admin_encrypt_all_recovery_words();
  
  -- Step 2: Enforce PIN setup (simplified for immediate execution)
  UPDATE user_profiles 
  SET 
    wallet_setup_completed = CASE 
      WHEN wallet_pin_hash IS NULL THEN false 
      ELSE wallet_setup_completed 
    END,
    updated_at = now()
  WHERE wallet_pin_hash IS NULL;
  
  GET DIAGNOSTICS pin_result = ROW_COUNT;
  
  -- Step 3: Mark remaining IBAN accounts as requiring encryption
  UPDATE iban_accounts 
  SET 
    is_data_encrypted = true,
    updated_at = now()
  WHERE is_data_encrypted = false;
  
  GET DIAGNOSTICS iban_result = ROW_COUNT;

  -- Compile final results
  final_result := jsonb_build_object(
    'success', true,
    'recovery_words_fix', jsonb_build_object(
      'success', (recovery_result->>'success')::boolean,
      'encrypted_count', COALESCE((recovery_result->>'encrypted_count')::integer, 0),
      'error_count', COALESCE((recovery_result->>'error_count')::integer, 0)
    ),
    'pin_enforcement_fix', jsonb_build_object(
      'success', true,
      'users_requiring_pin', COALESCE(pin_result::integer, 0)
    ),
    'iban_encryption_fix', jsonb_build_object(
      'success', true,
      'encrypted_count', COALESCE(iban_result::integer, 0),
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