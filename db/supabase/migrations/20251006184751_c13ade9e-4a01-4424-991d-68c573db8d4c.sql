-- Update get_wallet_recovery_words_secure to use proper schema and validation
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(user_uuid uuid, input_pin text, client_ip inet DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  pin_validation_result jsonb;
  recovery_words text[];
  words_encrypted boolean;
BEGIN
  -- Use the secure PIN validation function
  SELECT validate_wallet_pin_secure(user_uuid, input_pin, client_ip)
  INTO pin_validation_result;
  
  -- Return early if PIN validation failed
  IF NOT (pin_validation_result->>'success')::boolean THEN
    RETURN pin_validation_result;
  END IF;
  
  -- Get recovery words
  SELECT wallet_recovery_words, recovery_words_encrypted
  INTO recovery_words, words_encrypted
  FROM public.user_profiles
  WHERE user_id = user_uuid;
  
  IF recovery_words IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_recovery_words',
      'message', 'No recovery words found for this account'
    );
  END IF;
  
  -- Log successful access
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (user_uuid, 'recovery_words_accessed', 'wallet_security', 
    jsonb_build_object('encrypted', words_encrypted, 'timestamp', now()));
  
  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', recovery_words,
    'encrypted', words_encrypted,
    'access_method', pin_validation_result->>'access_method'
  );
END;
$$;