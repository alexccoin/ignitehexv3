-- Fix validation to only check recovery words when they're being modified
CREATE OR REPLACE FUNCTION public.validate_user_profile_security()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Validate email format
  IF NEW.email_address IS NOT NULL AND NOT NEW.email_address ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
    RAISE EXCEPTION 'Invalid email format';
  END IF;
  
  -- Validate full name (no script tags or suspicious content)
  IF NEW.full_name IS NOT NULL AND (
    NEW.full_name ILIKE '%<script%' OR 
    NEW.full_name ILIKE '%javascript:%' OR 
    NEW.full_name ILIKE '%on[a-z]%=%'
  ) THEN
    RAISE EXCEPTION 'Invalid characters in full name';
  END IF;
  
  RETURN NEW;
END;
$$;

-- Simplify the enhanced validation to be less restrictive
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption_enhanced()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only validate if recovery words are being explicitly updated to new values
  IF TG_OP = 'UPDATE' AND 
     NEW.wallet_recovery_words IS NOT NULL AND 
     NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words THEN
    
    -- If setting new recovery words, they should be encrypted
    IF NEW.recovery_words_encrypted = false THEN
      RAISE EXCEPTION 'SECURITY VIOLATION: New recovery words must be encrypted before storage.';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;