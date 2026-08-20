-- Fix the admin check function to properly work with the existing user_roles table
CREATE OR REPLACE FUNCTION public.is_admin(user_id UUID DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if user has admin role in user_roles table
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = $1 
    AND role = 'admin'
  );
END;
$function$;

-- Test the emergency security fixes function with proper admin check
CREATE OR REPLACE FUNCTION public.test_critical_security_fixes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
BEGIN
  -- Check admin access using the fixed function
  IF NOT is_admin(auth.uid()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required', 'user_id', auth.uid());
  END IF;
  
  -- Return test data to verify the function works
  RETURN jsonb_build_object(
    'success', true, 
    'message', 'Admin access verified', 
    'user_id', auth.uid(),
    'test_complete', true
  );
END;
$function$;