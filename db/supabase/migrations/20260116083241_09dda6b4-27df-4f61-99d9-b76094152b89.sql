-- Add seed_str_admin role to the app_role enum
ALTER TYPE app_role ADD VALUE IF NOT EXISTS 'seed_str_admin';

-- Create a function to check if user has seed_str_admin access
CREATE OR REPLACE FUNCTION public.has_seed_str_admin_access(check_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Check if user has admin or seed_str_admin role
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = check_user_id 
    AND role IN ('admin', 'seed_str_admin')
  );
END;
$$;