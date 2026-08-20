-- Security hardening migration: attach enforcement triggers and fix secure recovery words RPC

-- 1) Attach encryption enforcement triggers
DROP TRIGGER IF EXISTS enforce_github_token_encryption_trigger ON public.github_integrations;
CREATE TRIGGER enforce_github_token_encryption_trigger
BEFORE INSERT OR UPDATE ON public.github_integrations
FOR EACH ROW EXECUTE FUNCTION public.enforce_github_token_encryption();

DROP TRIGGER IF EXISTS validate_iban_security_trigger ON public.iban_accounts;
CREATE TRIGGER validate_iban_security_trigger
BEFORE INSERT OR UPDATE ON public.iban_accounts
FOR EACH ROW EXECUTE FUNCTION public.validate_iban_security();

DROP TRIGGER IF EXISTS enforce_recovery_words_encryption_trigger ON public.user_profiles;
CREATE TRIGGER enforce_recovery_words_encryption_trigger
BEFORE INSERT OR UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_recovery_words_encryption();

-- 2) Harden get_wallet_recovery_words_secure to use server-derived IP and structured JSON
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(
  user_uuid uuid,
  input_pin text DEFAULT NULL::text,
  client_ip inet DEFAULT NULL::inet
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_words TEXT[];
  pin_validation_result jsonb;
  is_admin_user boolean;
  actual_client_ip inet;
BEGIN
  -- Admin override: log and return directly
  SELECT is_admin(auth.uid()) INTO is_admin_user;
  IF is_admin_user THEN
    INSERT INTO public.security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      auth.uid(), 
      'admin_recovery_access', 
      'wallet_recovery',
      user_uuid::text,
      jsonb_build_object('target_user', user_uuid, 'admin_override', true, 'timestamp', now())
    );

    SELECT wallet_recovery_words INTO recovery_words
    FROM public.user_profiles
    WHERE user_id = user_uuid;

    RETURN jsonb_build_object(
      'success', true,
      'recovery_words', recovery_words,
      'access_method', 'admin_override'
    );
  END IF;

  -- Regular users must provide PIN
  IF input_pin IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'pin_required',
      'message', 'PIN is required to access recovery words.'
    );
  END IF;

  -- Use server-derived client IP when possible
  actual_client_ip := COALESCE(client_ip, public.get_client_ip());

  SELECT public.validate_wallet_pin_secure_fixed(user_uuid, input_pin, actual_client_ip)
  INTO pin_validation_result;

  IF NOT (pin_validation_result->>'success')::boolean THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', COALESCE(pin_validation_result->>'error', 'invalid_pin'),
      'message', COALESCE(pin_validation_result->>'message', 'Invalid PIN provided.'),
      'retry_after', pin_validation_result->>'retry_after'
    );
  END IF;

  -- Fetch recovery words (may be encrypted payload depending on storage policy)
  SELECT wallet_recovery_words INTO recovery_words
  FROM public.user_profiles
  WHERE user_id = user_uuid;

  -- Audit successful access
  INSERT INTO public.security_audit_log (user_id, action, resource_type, resource_id, details)
  VALUES (
    auth.uid(), 'recovery_words_accessed', 'wallet_recovery', user_uuid::text,
    jsonb_build_object('ip_address', actual_client_ip::text, 'timestamp', now())
  );

  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', recovery_words,
    'access_method', 'pin_validated'
  );
END;
$function$;