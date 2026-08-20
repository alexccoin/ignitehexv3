-- Drop and recreate functions with proper search paths
DROP FUNCTION IF EXISTS public.is_admin(uuid);

-- Recreate is_admin function with proper search path
CREATE OR REPLACE FUNCTION public.is_admin(check_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = check_user_id 
    AND role = 'admin'
  );
END;
$$;