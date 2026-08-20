-- Create secure function to validate PIN and retrieve recovery words
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(
  user_uuid uuid,
  input_pin text,
  client_ip text DEFAULT '0.0.0.0'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  stored_pin_hash text;
  user_recovery_words text[];
  pin_valid boolean;
BEGIN
  -- Get user's PIN hash and recovery words
  SELECT wallet_pin_hash, wallet_recovery_words
  INTO stored_pin_hash, user_recovery_words
  FROM user_profiles
  WHERE user_id = user_uuid;

  -- Check if user has a PIN set
  IF stored_pin_hash IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN has been set for this account'
    );
  END IF;

  -- Verify the PIN
  pin_valid := verify_pin_secure(input_pin, stored_pin_hash);

  IF NOT pin_valid THEN
    -- Log failed attempt
    INSERT INTO security_audit_log (user_id, action, resource_type, details)
    VALUES (
      user_uuid,
      'pin_verification_failed',
      'wallet_access',
      jsonb_build_object('client_ip', client_ip, 'timestamp', now())
    );

    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin',
      'message', 'Invalid PIN'
    );
  END IF;

  -- PIN is valid, mark recovery words as shown
  UPDATE user_profiles
  SET recovery_words_shown = true,
      updated_at = now()
  WHERE user_id = user_uuid;

  -- Log successful access
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    user_uuid,
    'pin_verification_success',
    'wallet_access',
    jsonb_build_object('client_ip', client_ip, 'timestamp', now())
  );

  -- Return success with recovery words
  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', user_recovery_words,
    'access_method', 'pin_verification'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'system_error',
    'message', 'An error occurred during verification'
  );
END;
$function$;