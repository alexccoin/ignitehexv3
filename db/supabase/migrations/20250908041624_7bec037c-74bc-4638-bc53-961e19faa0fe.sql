-- Fix is_admin function with proper search path using exact same signature
CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- Handle null input
  IF check_user_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Check if user has admin role in user_roles table
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = check_user_id 
    AND role = 'admin'
  );
END;
$function$;