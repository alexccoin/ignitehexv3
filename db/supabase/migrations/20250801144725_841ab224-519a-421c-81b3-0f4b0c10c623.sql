-- Create a comprehensive admin view function
CREATE OR REPLACE FUNCTION get_all_users_admin()
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
  last_login timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;

  RETURN QUERY
  SELECT 
    up.id,
    up.user_id,
    up.email_address,
    up.full_name,
    up.str_domain_owned,
    up.status,
    up.user_status,
    up.created_at,
    up.updated_at,
    COALESCE(ur.role, 'user'::app_role) as role,
    COALESCE(p.updated_at, up.created_at) as last_login
  FROM user_profiles up
  LEFT JOIN user_roles ur ON up.user_id = ur.user_id
  LEFT JOIN profiles p ON up.user_id = p.user_id
  ORDER BY up.created_at DESC;
END;
$$;

-- Update user status function
CREATE OR REPLACE FUNCTION update_user_account_status(target_user_id uuid, new_status account_status)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  
  -- Update the user status
  UPDATE user_profiles 
  SET status = new_status, updated_at = now()
  WHERE user_id = target_user_id;
  
  -- Return true if update was successful
  RETURN FOUND;
END;
$$;

-- Update user badge status function
CREATE OR REPLACE FUNCTION update_user_badge_status(target_user_id uuid, new_user_status user_status)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Check if the requesting user is admin
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin privileges required.';
  END IF;
  
  -- Update the user badge status
  UPDATE user_profiles 
  SET user_status = new_user_status, updated_at = now()
  WHERE user_id = target_user_id;
  
  -- Return true if update was successful
  RETURN FOUND;
END;
$$;