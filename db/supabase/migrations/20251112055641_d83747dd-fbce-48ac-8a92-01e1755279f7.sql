-- Create a new RPC function that explicitly returns unlimited rows
-- This bypasses PostgREST's max-rows limit by using a different pattern

DROP FUNCTION IF EXISTS public.get_all_users_admin_unlimited();

CREATE OR REPLACE FUNCTION public.get_all_users_admin_unlimited()
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Return all users as JSON array (bypasses PostgREST limits)
  RETURN QUERY
  SELECT json_agg(
    json_build_object(
      'id', up.id,
      'user_id', au.id,
      'email_address', COALESCE(up.email_address, au.email),
      'full_name', COALESCE(up.full_name, 'No Profile Created'),
      'str_domain_owned', COALESCE(up.str_domain_owned, 'None'),
      'status', COALESCE(up.status, 'pending'::account_status),
      'user_status', COALESCE(up.user_status, 'standard'::user_status),
      'created_at', COALESCE(up.created_at, au.created_at),
      'updated_at', COALESCE(up.updated_at, au.updated_at),
      'role', COALESCE(ur.role, 'user'::app_role),
      'last_login', COALESCE(au.last_sign_in_at, au.created_at),
      'email_confirmed', (au.email_confirmed_at IS NOT NULL),
      'auth_created_at', au.created_at,
      'ip_address', up.ip_address,
      'country', up.country,
      'city', up.city,
      'region', up.region
    )
  )
  FROM auth.users au
  LEFT JOIN user_profiles up ON au.id = up.user_id
  LEFT JOIN user_roles ur ON au.id = ur.user_id
  ORDER BY au.created_at DESC;
END;
$function$;

-- Also update the original function to use SETOF pattern which is more efficient
DROP FUNCTION IF EXISTS public.get_all_users_admin();

CREATE OR REPLACE FUNCTION public.get_all_users_admin()
RETURNS SETOF json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  result_json json;
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  -- Build complete JSON array of all users
  SELECT json_agg(user_data ORDER BY created_at DESC)
  INTO result_json
  FROM (
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
      au.created_at as auth_created_at,
      up.ip_address,
      up.country,
      up.city,
      up.region
    FROM auth.users au
    LEFT JOIN user_profiles up ON au.id = up.user_id
    LEFT JOIN user_roles ur ON au.id = ur.user_id
  ) user_data;

  -- Return the complete array as a single JSON value
  RETURN NEXT result_json;
END;
$function$;

-- Add comment explaining the PostgREST limitation
COMMENT ON FUNCTION public.get_all_users_admin() IS 
'Returns all users as a single JSON array to bypass PostgREST max-rows limit of 1000. 
For optimal performance with 10,000+ users, consider increasing PostgREST max_rows 
in Supabase project settings: Settings > API > Config > max-rows = 10000';