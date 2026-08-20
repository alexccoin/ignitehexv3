-- Drop the audit trigger that's causing the field access error
DROP TRIGGER IF EXISTS audit_user_profiles ON user_profiles;

-- Also drop any other triggers that might be using log_sensitive_data_access on user_profiles
DROP TRIGGER IF EXISTS log_sensitive_data_access_trigger ON user_profiles;
DROP TRIGGER IF EXISTS sensitive_data_audit_trigger ON user_profiles;

-- Create a simpler audit trigger for user_profiles that doesn't reference non-existent fields
CREATE OR REPLACE FUNCTION public.log_user_profile_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details,
    ip_address
  ) VALUES (
    auth.uid(),
    TG_OP || '_user_profile',
    'user_profiles',
    COALESCE(NEW.id, OLD.id)::text,
    jsonb_build_object(
      'operation', TG_OP,
      'table', 'user_profiles',
      'timestamp', now(),
      'has_encrypted_recovery_words', CASE 
        WHEN TG_OP = 'DELETE' THEN COALESCE(OLD.recovery_words_encrypted, false)
        ELSE COALESCE(NEW.recovery_words_encrypted, false)
      END
    ),
    get_client_ip()
  );
  
  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Create the corrected audit trigger for user_profiles
CREATE TRIGGER audit_user_profiles
AFTER INSERT OR UPDATE OR DELETE ON user_profiles
FOR EACH ROW EXECUTE FUNCTION log_user_profile_access();