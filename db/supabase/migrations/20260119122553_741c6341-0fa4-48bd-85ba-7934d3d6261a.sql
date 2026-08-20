-- Update verify_admin_access to include seed_str_admin role
CREATE OR REPLACE FUNCTION public.verify_admin_access(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_role app_role;
  result jsonb;
BEGIN
  -- Get user role
  SELECT get_user_role(check_user_id) INTO user_role;
  
  -- Log admin access attempt
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (
    check_user_id, 
    'admin_access_check', 
    'admin_functions',
    jsonb_build_object('role', user_role, 'timestamp', now())
  );
  
  -- Check for admin or seed_str_admin roles
  IF user_role IN ('admin'::app_role, 'seed_str_admin'::app_role) THEN
    RETURN jsonb_build_object(
      'success', true,
      'role', user_role,
      'message', 'Admin access granted.'
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'role', COALESCE(user_role::text, 'none'),
      'error', 'insufficient_privileges',
      'message', 'Admin access required.'
    );
  END IF;
END;
$function$;