
CREATE OR REPLACE FUNCTION public.get_all_users_admin()
 RETURNS SETOF json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  result_json json;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

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
      COALESCE(
        (SELECT ur.role FROM user_roles ur
          WHERE ur.user_id = au.id
          ORDER BY CASE ur.role
            WHEN 'admin'::app_role THEN 1
            WHEN 'seed_str_admin'::app_role THEN 2
            ELSE 3 END
          LIMIT 1),
        'user'::app_role
      ) as role,
      COALESCE(au.last_sign_in_at, au.created_at) as last_login,
      (au.email_confirmed_at IS NOT NULL) as email_confirmed,
      au.created_at as auth_created_at,
      up.ip_address,
      up.country,
      up.city,
      up.region
    FROM auth.users au
    LEFT JOIN user_profiles up ON au.id = up.user_id
  ) user_data;

  RETURN NEXT result_json;
END;
$function$;
