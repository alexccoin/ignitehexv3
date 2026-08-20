-- Fix the log_sensitive_data_access function to handle missing encryption fields
CREATE OR REPLACE FUNCTION public.log_sensitive_data_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
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
          WHEN TG_TABLE_NAME = 'user_profiles' THEN 
            COALESCE(
              CASE WHEN TG_OP = 'DELETE' THEN OLD.recovery_words_encrypted ELSE NEW.recovery_words_encrypted END, 
              false
            )
          WHEN TG_TABLE_NAME = 'iban_accounts' THEN 
            COALESCE(
              CASE WHEN TG_OP = 'DELETE' THEN OLD.is_data_encrypted ELSE NEW.is_data_encrypted END, 
              false
            )
          WHEN TG_TABLE_NAME = 'github_integrations' THEN 
            COALESCE(
              CASE WHEN TG_OP = 'DELETE' THEN OLD.is_token_encrypted ELSE NEW.is_token_encrypted END, 
              false
            )
          ELSE false
        END
      ),
      get_client_ip()
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$function$;