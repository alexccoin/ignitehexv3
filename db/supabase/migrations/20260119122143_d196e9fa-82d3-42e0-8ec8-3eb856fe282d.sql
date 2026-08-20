-- Update is_admin function to include super_admin and seed_str_admin roles
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
  
  -- Check if user has admin, super_admin, or seed_str_admin role in user_roles table
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = check_user_id 
    AND role IN ('admin', 'super_admin', 'seed_str_admin')
  );
END;
$function$;