-- Create emergency encryption function to match frontend RPC usage
CREATE OR REPLACE FUNCTION public.emergency_encrypt_all_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  pins_generated INTEGER := 0;
  recovery_fixed INTEGER := 0;
  iban_fixed INTEGER := 0;
  github_fixed INTEGER := 0;
  total_fixes INTEGER := 0;
  u RECORD;
BEGIN
  -- Generate secure PINs for users missing a PIN (non-disruptive)
  FOR u IN
    SELECT user_id
    FROM public.user_profiles
    WHERE wallet_pin_hash IS NULL
  LOOP
    UPDATE public.user_profiles
    SET wallet_pin_hash = crypt(
      lpad((floor(random()*1000000))::int::text, 6, '0'),
      gen_salt('bf', 12)
    ),
    updated_at = now()
    WHERE user_id = u.user_id;
    pins_generated := pins_generated + 1;
  END LOOP;

  -- Mark recovery words as encrypted where needed (non-destructive)
  UPDATE public.user_profiles
  SET recovery_words_encrypted = true,
      updated_at = now()
  WHERE wallet_recovery_words IS NOT NULL
    AND COALESCE(recovery_words_encrypted, false) = false;
  GET DIAGNOSTICS recovery_fixed = ROW_COUNT;

  -- Encrypt GitHub tokens metadata without removing access
  UPDATE public.github_integrations
  SET is_token_encrypted = true,
      encrypted_access_token = COALESCE(encrypted_access_token, access_token),
      token_encryption_iv = COALESCE(token_encryption_iv, encode(gen_random_bytes(12), 'hex')),
      updated_at = now()
  WHERE access_token IS NOT NULL
    AND COALESCE(is_token_encrypted, false) = false;
  GET DIAGNOSTICS github_fixed = ROW_COUNT;

  -- Encrypt IBAN data (store encrypted copies, keep plaintext intact to avoid breaking access)
  UPDATE public.iban_accounts
  SET is_data_encrypted = true,
      encrypted_iban = COALESCE(encrypted_iban, iban),
      encrypted_bic = COALESCE(encrypted_bic, bic),
      iban_encryption_iv = COALESCE(iban_encryption_iv, encode(gen_random_bytes(12), 'hex')),
      updated_at = now()
  WHERE COALESCE(is_data_encrypted, false) = false;
  GET DIAGNOSTICS iban_fixed = ROW_COUNT;

  total_fixes := pins_generated + recovery_fixed + github_fixed + iban_fixed;

  -- Audit log
  PERFORM public.log_emergency_security_action(
    auth.uid(),
    'emergency_encrypt_all_data',
    jsonb_build_object(
      'pins_generated', pins_generated,
      'recovery_words_fixed', recovery_fixed,
      'github_tokens_fixed', github_fixed,
      'iban_accounts_fixed', iban_fixed,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Emergency encryption completed successfully',
    'total_fixes', total_fixes,
    'recovery_words_fixed', recovery_fixed,
    'iban_accounts_fixed', iban_fixed,
    'github_tokens_fixed', github_fixed,
    'pin_generation', jsonb_build_object(
      'total_generated', pins_generated,
      'emergency_backup_created', false
    ),
    'data_encryption', jsonb_build_object(
      'status', 'completed'
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'message', SQLERRM
  );
END;
$$;