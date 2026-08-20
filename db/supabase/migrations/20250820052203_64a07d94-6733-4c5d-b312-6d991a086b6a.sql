-- CRITICAL SECURITY FIXES - Phase 1B: Fix Function Search Path Issues

-- Fix search_path for all functions to prevent schema injection attacks

-- Fix validate_recovery_words_encryption function
CREATE OR REPLACE FUNCTION validate_recovery_words_encryption()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- If recovery words are provided, they must be encrypted
  IF NEW.wallet_recovery_words IS NOT NULL AND array_length(NEW.wallet_recovery_words, 1) > 0 THEN
    IF COALESCE(NEW.recovery_words_encrypted, false) = false THEN
      RAISE EXCEPTION 'Recovery words must be encrypted. Use encryption migration first.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Fix validate_iban_encryption function  
CREATE OR REPLACE FUNCTION validate_iban_encryption()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- If IBAN data exists and is not marked as encrypted, require encryption
  IF (NEW.iban IS NOT NULL AND NEW.iban != '***ENCRYPTED***') OR 
     (NEW.bic IS NOT NULL AND NEW.bic != '***ENCRYPTED***') THEN
    IF COALESCE(NEW.is_data_encrypted, false) = false THEN
      RAISE EXCEPTION 'IBAN data must be encrypted. Use encryption migration first.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Fix log_sensitive_data_access function
CREATE OR REPLACE FUNCTION log_sensitive_data_access()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Log all access to sensitive financial and personal data
  IF TG_TABLE_NAME IN ('user_profiles', 'transactions', 'iban_accounts', 'prepaid_cards', 'github_integrations') THEN
    INSERT INTO public.security_audit_log (
      user_id,
      action,
      resource_type,
      resource_id,
      details,
      ip_address
    ) VALUES (
      auth.uid(),
      TG_OP || '_sensitive_data',
      TG_TABLE_NAME,
      COALESCE(NEW.id, OLD.id)::text,
      jsonb_build_object(
        'operation', TG_OP,
        'table', TG_TABLE_NAME,
        'timestamp', now(),
        'has_encrypted_data', CASE 
          WHEN TG_TABLE_NAME = 'user_profiles' THEN COALESCE(NEW.recovery_words_encrypted, OLD.recovery_words_encrypted, false)
          WHEN TG_TABLE_NAME = 'iban_accounts' THEN COALESCE(NEW.is_data_encrypted, OLD.is_data_encrypted, false)
          WHEN TG_TABLE_NAME = 'github_integrations' THEN COALESCE(NEW.is_token_encrypted, OLD.is_token_encrypted, false)
          ELSE false
        END
      ),
      get_client_ip()
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;