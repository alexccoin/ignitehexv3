-- Add missing security logging functions for security fixes

-- Drop existing functions that might conflict
DROP FUNCTION IF EXISTS public.log_emergency_security_action(uuid, text, jsonb);
DROP FUNCTION IF EXISTS public.log_security_event(text, text, text, jsonb);

-- Create get_client_ip function for IP logging
CREATE OR REPLACE FUNCTION public.get_client_ip()
RETURNS inet
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Return a default IP for now since we can't access real client IP in this context
  RETURN '127.0.0.1'::inet;
END;
$function$;

-- Create log_security_event function
CREATE OR REPLACE FUNCTION public.log_security_event(
  action_name text,
  resource_type_name text,
  resource_id_val text DEFAULT NULL,
  details_json jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details,
    ip_address
  ) VALUES (
    auth.uid(),
    action_name,
    resource_type_name,
    resource_id_val,
    details_json,
    get_client_ip()
  );
END;
$function$;

-- Create log_emergency_security_action function
CREATE OR REPLACE FUNCTION public.log_emergency_security_action(
  action_user_id uuid,
  action_type text,
  action_details jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details,
    ip_address
  ) VALUES (
    action_user_id,
    action_type,
    'emergency_security',
    action_details,
    get_client_ip()
  );
END;
$function$;