-- Fix the search path security warnings by setting explicit search_path
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
  
  -- Only validate recovery words encryption if recovery words are being actively set/changed
  IF (TG_OP = 'INSERT' AND NEW.wallet_recovery_words IS NOT NULL) OR 
     (TG_OP = 'UPDATE' AND NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words AND NEW.wallet_recovery_words IS NOT NULL) THEN
    IF NEW.recovery_words_encrypted = false THEN
      RAISE EXCEPTION 'Recovery words must be encrypted when stored';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Also fix the enhanced validation function
CREATE OR REPLACE FUNCTION public.validate_recovery_words_encryption_enhanced()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only validate if recovery words are being actively set/changed
  IF (TG_OP = 'INSERT' AND NEW.wallet_recovery_words IS NOT NULL) OR 
     (TG_OP = 'UPDATE' AND NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words AND NEW.wallet_recovery_words IS NOT NULL) THEN
    
    -- Ensure recovery words are encrypted when being set
    IF NEW.recovery_words_encrypted = false THEN
      RAISE EXCEPTION 'SECURITY VIOLATION: Recovery words must be encrypted before storage. Plaintext storage is prohibited.';
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$;