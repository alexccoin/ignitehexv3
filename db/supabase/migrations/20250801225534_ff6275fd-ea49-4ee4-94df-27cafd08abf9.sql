-- Drop the existing function first
DROP FUNCTION IF EXISTS public.get_all_users_admin();

-- Create the updated function to show ALL users from auth.users table
-- including those who don't have profiles yet and those with pending status
CREATE OR REPLACE FUNCTION public.get_all_users_admin()
RETURNS TABLE(
  id uuid, 
  user_id uuid, 
  email_address text, 
  full_name text, 
  str_domain_owned text, 
  status account_status, 
  user_status user_status, 
  created_at timestamp with time zone, 
  updated_at timestamp with time zone, 
  role app_role, 
  last_login timestamp with time zone,
  email_confirmed boolean,
  auth_created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  RETURN QUERY
  SELECT 
    up.id,
    au.id as user_id,
    COALESCE(up.email_address, au.email) as email_address,
    COALESCE(up.full_name, 'No Profile Created') as full_name,
    COALESCE(up.str_domain_owned, 'None') as str_domain_owned,
    COALESCE(up.status, 'pending'::account_status) as status,
    COALESCE(up.user_status, 'standard'::user_status) as user_status,
    COALESCE(up.created_at, au.created_at) as created_at,
    COALESCE(up.updated_at, au.updated_at) as updated_at,
    COALESCE(ur.role, 'user'::app_role) as role,
    COALESCE(au.last_sign_in_at, au.created_at) as last_login,
    (au.email_confirmed_at IS NOT NULL) as email_confirmed,
    au.created_at as auth_created_at
  FROM auth.users au
  LEFT JOIN user_profiles up ON au.id = up.user_id
  LEFT JOIN user_roles ur ON au.id = ur.user_id
  ORDER BY au.created_at DESC;
END;
$function$;