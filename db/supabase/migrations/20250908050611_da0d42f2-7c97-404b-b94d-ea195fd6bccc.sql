-- Fix the specific function causing the search path warning
-- The enforce_no_plaintext_sensitive_data function needs SET search_path

CREATE OR REPLACE FUNCTION public.enforce_no_plaintext_sensitive_data()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Prevent plaintext GitHub tokens
  IF TG_TABLE_NAME = 'github_integrations' THEN
    IF NEW.access_token IS NOT NULL AND NEW.is_token_encrypted = false THEN
      RAISE EXCEPTION 'Plaintext GitHub tokens are not allowed. Use encrypted_access_token instead.';
    END IF;
  END IF;

  -- Prevent plaintext IBAN/BIC when encryption is marked as required
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    IF NEW.is_data_encrypted = true AND (NEW.iban NOT LIKE '****%' OR NEW.bic NOT LIKE '***%') THEN
      RAISE EXCEPTION 'IBAN/BIC must be masked when marked as encrypted.';
    END IF;
  END IF;

  -- Prevent plaintext recovery words when encryption flag is set
  IF TG_TABLE_NAME = 'user_profiles' THEN
    IF NEW.recovery_words_encrypted = true AND NEW.wallet_recovery_words IS NOT NULL THEN
      -- Check if it looks like plaintext (simple heuristic)
      IF array_length(NEW.wallet_recovery_words, 1) > 0 AND 
         length(NEW.wallet_recovery_words[1]) < 50 THEN
        RAISE EXCEPTION 'Recovery words must be properly encrypted when encryption flag is true.';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;