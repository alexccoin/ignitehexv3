-- Make get_wallet_recovery_words_secure read-only to avoid RLS violations
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
  -- Attempt to cast client_ip; ignore failures
  BEGIN
    ip_inet := client_ip::inet;
  EXCEPTION WHEN OTHERS THEN
    ip_inet := NULL;
  END;

  -- Delegate to central validator (handles bcrypt/legacy + rate limits)
  SELECT public.validate_wallet_pin_secure(user_uuid, input_pin, ip_inet)
  INTO validation;

  IF COALESCE((validation->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN validation; -- propagate structured error
  END IF;

  -- Read-only fetch of recovery words
  SELECT wallet_recovery_words
  INTO words
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', words,
    'access_method', 'pin_verification'
  );
END;
$function$;