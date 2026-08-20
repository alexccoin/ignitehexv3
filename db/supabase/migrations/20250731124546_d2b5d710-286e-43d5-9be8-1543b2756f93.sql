-- Fix the security warning by setting search_path for the function
CREATE OR REPLACE FUNCTION public.check_user_or_system()
RETURNS TRIGGER AS $$
BEGIN
  -- Allow system/global pool UUIDs to bypass user validation
  IF NEW.user_id = '00000000-0000-0000-0000-000000000001' THEN
    RETURN NEW;
  END IF;
  
  -- For regular users, check if they exist in auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.user_id) THEN
    RAISE EXCEPTION 'User does not exist';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;