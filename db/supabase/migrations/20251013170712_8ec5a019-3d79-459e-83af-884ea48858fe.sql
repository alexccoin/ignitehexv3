-- Fix PIN verification by delegating to bcrypt-aware validator
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
  ip_inet inet := NULL;
  validation jsonb;
  words text[];
BEGIN
  -- Safely cast client_ip to inet if possible
  BEGIN
    ip_inet := client_ip::inet;
  EXCEPTION WHEN OTHERS THEN
    ip_inet := NULL;
  END;

  -- Use centralized validator that supports bcrypt, legacy and rate limiting
  SELECT public.validate_wallet_pin_secure(user_uuid, input_pin, ip_inet)
  INTO validation;

  IF COALESCE((validation->>'success')::boolean, false) IS DISTINCT FROM true THEN
    -- Return the validation payload as-is (includes error, retry info, etc.)
    RETURN validation;
  END IF;

  -- Fetch recovery words (may be encrypted depending on profile state)
  SELECT wallet_recovery_words
  INTO words
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  -- Mark words as shown and audit
  UPDATE public.user_profiles
  SET recovery_words_shown = true,
      updated_at = now()
  WHERE user_id = user_uuid;

  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (
    user_uuid,
    'wallet_pin_verified_dialog',
    'wallet_access',
    jsonb_build_object('client_ip', client_ip, 'timestamp', now())
  );

  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', words,
    'access_method', 'pin_verification'
  );
END;
$function$;