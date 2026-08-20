-- Fix the remaining key security functions that are showing in the security scan
-- These functions are critical and need proper search paths

-- Fix get_client_ip function
DROP FUNCTION IF EXISTS public.get_client_ip();
CREATE OR REPLACE FUNCTION public.get_client_ip()
RETURNS inet
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Try to get real client IP from headers set by reverse proxies
  RETURN COALESCE(
    inet(current_setting('request.headers', true)::json->>'x-forwarded-for'),
    inet(current_setting('request.headers', true)::json->>'x-real-ip'), 
    inet(current_setting('request.headers', true)::json->>'cf-connecting-ip'),
    '127.0.0.1'::inet
  );
EXCEPTION WHEN OTHERS THEN
  RETURN '127.0.0.1'::inet;
END;
$$;

-- Fix check_user_or_system function  
DROP FUNCTION IF EXISTS public.check_user_or_system();
CREATE OR REPLACE FUNCTION public.check_user_or_system()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
$$;