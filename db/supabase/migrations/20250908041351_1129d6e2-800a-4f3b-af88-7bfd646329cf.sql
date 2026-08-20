-- Fix the trigger function that's likely causing the security warning
CREATE OR REPLACE FUNCTION public.enforce_pin_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- Ensure wallet PIN is set for wallet setup completion
  IF NEW.wallet_setup_completed = true AND NEW.wallet_pin_hash IS NULL THEN
    RAISE EXCEPTION 'Wallet PIN is required before completing wallet setup';
  END IF;
  
  -- Ensure recovery words are encrypted when flagged
  IF NEW.recovery_words_encrypted = true AND NEW.wallet_recovery_words IS NOT NULL THEN
    -- Validate that recovery words look encrypted (should not be readable text)
    FOR i IN 1..array_length(NEW.wallet_recovery_words, 1) LOOP
      IF NEW.wallet_recovery_words[i] NOT LIKE '{"encrypted"%' THEN
        RAISE EXCEPTION 'Recovery words must be properly encrypted when recovery_words_encrypted is true';
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$function$;