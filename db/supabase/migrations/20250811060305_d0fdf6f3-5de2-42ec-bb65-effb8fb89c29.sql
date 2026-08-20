-- Create assign_user_role function for promoting users to admin, moderator, or support roles
CREATE OR REPLACE FUNCTION public.assign_user_role(target_email text, user_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  target_user_id uuid;
BEGIN
  -- Find user by email in profiles table
  SELECT user_id INTO target_user_id
  FROM public.profiles
  WHERE email = target_email;
  
  -- If user not found, return false
  IF target_user_id IS NULL THEN
    RETURN false;
  END IF;
  
  -- Delete existing role if any
  DELETE FROM public.user_roles
  WHERE user_id = target_user_id;
  
  -- Insert new role
  INSERT INTO public.user_roles (user_id, role, created_by)
  VALUES (target_user_id, user_role::app_role, auth.uid());
  
  RETURN true;
END;
$$;