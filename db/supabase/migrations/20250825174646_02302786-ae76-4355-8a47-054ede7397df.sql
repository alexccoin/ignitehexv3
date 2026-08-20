-- Fix the recovery words validation trigger to allow proper encryption workflows
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only for user_profiles table - check recovery_words_encrypted field
  -- Allow encryption workflows, just log the transition
  
  -- If marking as encrypted, optionally clear plaintext recovery words
  IF NEW.recovery_words_encrypted = true AND OLD.recovery_words_encrypted = false THEN
    -- This is an encryption operation - clear plaintext recovery words for security
    NEW.wallet_recovery_words := NULL;
  END IF;
  
  -- If marking as not encrypted and there are encrypted fields, warn but allow
  IF NEW.recovery_words_encrypted = false AND NEW.recovery_words_iv IS NOT NULL THEN
    -- Log this transition but don't block it
    RAISE NOTICE 'Recovery words encryption flag set to false but encrypted data present';
  END IF;
  
  RETURN NEW;
END;
$function$;