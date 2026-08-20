-- Grant admin role to alex@strlabs.io
DO $$
DECLARE
  target_user_id uuid;
BEGIN
  -- Get user_id from auth.users
  SELECT id INTO target_user_id
  FROM auth.users
  WHERE email = 'alex@strlabs.io';

  -- Insert admin role if user exists
  IF target_user_id IS NOT NULL THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (target_user_id, 'admin'::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
    
    RAISE NOTICE 'Admin role granted to alex@strlabs.io (user_id: %)', target_user_id;
  ELSE
    RAISE NOTICE 'User alex@strlabs.io not found in auth.users';
  END IF;
END $$;