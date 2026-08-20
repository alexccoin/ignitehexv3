-- Relax the plaintext recovery words enforcement to only run when sensitive fields change
CREATE OR REPLACE FUNCTION public.prevent_plaintext_recovery_words()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only enforce encryption when actually modifying recovery words
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- Block only when recovery words are being set/changed without encryption
    IF (TG_OP = 'INSERT' AND NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false) OR
       (TG_OP = 'UPDATE' AND NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words AND NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false) THEN
      RAISE EXCEPTION 'Recovery words must be encrypted. Set recovery_words_encrypted = true';
    END IF;
  END IF;

  -- For GitHub integrations - only block when actually setting tokens
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF (TG_OP = 'INSERT' AND NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false) OR
       (TG_OP = 'UPDATE' AND NEW.access_token IS DISTINCT FROM OLD.access_token AND NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false) THEN
      RAISE EXCEPTION 'GitHub tokens must be encrypted. Set is_token_encrypted = true';
    END IF;
  END IF;

  -- For IBAN accounts - only block when actually setting sensitive data
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF (TG_OP = 'INSERT' AND NEW.is_data_encrypted = false AND (NEW.iban IS NOT NULL OR NEW.bic IS NOT NULL)) OR
       (TG_OP = 'UPDATE' AND NEW.is_data_encrypted = false AND 
        ((NEW.iban IS DISTINCT FROM OLD.iban AND NEW.iban IS NOT NULL) OR 
         (NEW.bic IS DISTINCT FROM OLD.bic AND NEW.bic IS NOT NULL))) THEN
      RAISE EXCEPTION 'IBAN data must be encrypted. Set is_data_encrypted = true';
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Simplify approval function to avoid touching encryption flags
CREATE OR REPLACE FUNCTION public.update_user_account_status(target_user_id uuid, new_status account_status)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Update only the status
  UPDATE user_profiles 
  SET status = new_status, updated_at = now()
  WHERE user_id = target_user_id;

  RETURN FOUND;
END;
$$;