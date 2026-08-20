-- Update the handle_new_user function to automatically grant pool access
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- Insert user profile
  INSERT INTO public.profiles (user_id, email, role)
  VALUES (NEW.id, NEW.email, 'user');
  
  -- Automatically grant pool access to new users
  INSERT INTO public.pool_access (user_id, granted_by, is_active, expires_at)
  VALUES (NEW.id, NEW.id, true, NULL);
  
  RETURN NEW;
END;
$function$;