-- Fix is_admin function to properly cast to app_role enum
CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Handle null input
  IF check_user_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Check if user has admin or seed_str_admin role in user_roles table
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = check_user_id 
    AND role IN ('admin'::app_role, 'seed_str_admin'::app_role)
  );
END;
$function$;