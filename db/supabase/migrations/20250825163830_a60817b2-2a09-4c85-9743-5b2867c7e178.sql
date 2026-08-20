-- Fix trigger error by checking for field existence before accessing it
-- First, let's see what triggers might be causing issues and fix the IBAN validation trigger

CREATE OR REPLACE FUNCTION public.validate_iban_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only proceed if this is actually an iban_accounts table operation
  -- and the record has the is_data_encrypted field
  IF TG_TABLE_NAME = 'iban_accounts' THEN
    -- Ensure IBAN/BIC data is encrypted when is_data_encrypted is true
    IF NEW.is_data_encrypted = true THEN
      -- If marked as encrypted, ensure encrypted fields are populated
      IF NEW.encrypted_iban IS NULL OR NEW.encrypted_bic IS NULL THEN
        RAISE EXCEPTION 'Encrypted IBAN and BIC fields must be populated when is_data_encrypted is true.';
      END IF;
      
      -- Mask plaintext fields when encrypted
      IF length(NEW.iban) > 8 THEN
        NEW.iban := left(NEW.iban, 4) || repeat('*', length(NEW.iban) - 8) || right(NEW.iban, 4);
      END IF;
      IF length(NEW.bic) > 6 THEN
        NEW.bic := left(NEW.bic, 3) || repeat('*', length(NEW.bic) - 6) || right(NEW.bic, 3);
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Also fix the GitHub token validation trigger to only apply to github_integrations table
CREATE OR REPLACE FUNCTION public.validate_github_token_security()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only proceed if this is actually a github_integrations table operation
  IF TG_TABLE_NAME = 'github_integrations' THEN
    -- Prevent storing plaintext tokens
    IF NEW.access_token IS NOT NULL THEN
      RAISE EXCEPTION 'Plaintext GitHub access_token is not allowed. Use encrypted_access_token with is_token_encrypted=true.';
    END IF;
    
    -- Ensure encrypted tokens are properly marked
    IF (NEW.encrypted_access_token IS NULL) OR (COALESCE(NEW.is_token_encrypted, false) = false) THEN
      RAISE EXCEPTION 'Encrypted token and is_token_encrypted=true are required.';
    END IF;
    
    -- Validate GitHub username format for security
    IF NEW.github_username IS NOT NULL AND (
      length(NEW.github_username) > 39 OR 
      NEW.github_username ~ '[^a-zA-Z0-9\-]'
    ) THEN
      RAISE EXCEPTION 'Invalid GitHub username format';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Fix the recovery words validation trigger
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Only proceed if this is actually a user_profiles table operation
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- Ensure recovery words are encrypted when stored
    IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = false THEN
      RAISE EXCEPTION 'Recovery words must be encrypted before storage. Use encrypted format only.';
    END IF;
    
    -- Validate encrypted recovery words structure if present
    IF NEW.wallet_recovery_words IS NOT NULL AND NEW.recovery_words_encrypted = true THEN
      -- Ensure recovery words look encrypted (basic validation)
      IF array_length(NEW.wallet_recovery_words, 1) > 0 THEN
        -- Check if any word looks like plaintext (common English words that shouldn't appear in encrypted data)
        IF EXISTS (
          SELECT 1 FROM unnest(NEW.wallet_recovery_words) AS word 
          WHERE word IN ('abandon', 'ability', 'able', 'account', 'achieve', 'address', 'adult', 'advance', 'agent', 'album', 'almost', 'alone', 'already', 'always', 'amount', 'ancient', 'another', 'answer', 'anxiety', 'appear', 'approve', 'argue', 'around', 'arrive', 'article', 'artist', 'assume', 'attack', 'august', 'author', 'autumn', 'average', 'awake', 'aware', 'balance', 'barely', 'battle', 'beauty', 'become', 'before', 'begin', 'behave', 'behind', 'believe', 'below', 'better', 'between', 'beyond', 'bicycle', 'biology', 'black', 'blanket', 'blood', 'board', 'bottom', 'brain', 'brand', 'brave', 'bread', 'bright', 'bring', 'broken', 'brother', 'brown', 'build', 'burst', 'business', 'button')
        ) THEN
          -- Allow migration placeholders but warn about plaintext
          IF NOT EXISTS (
            SELECT 1 FROM unnest(NEW.wallet_recovery_words) AS word 
            WHERE word LIKE '%MIGRATION_PLACEHOLDER_%'
          ) THEN
            RAISE EXCEPTION 'Recovery words appear to contain plaintext mnemonic words. Use encrypted format only.';
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;