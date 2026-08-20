-- Fix remaining functions with mutable search paths
-- This addresses the security linter warning: "Function Search Path Mutable"

-- Update all functions that don't have SET search_path = 'public'
-- Note: We'll recreate key functions to ensure they have the proper search path

-- Fix get_user_role function
DROP FUNCTION IF EXISTS public.get_user_role(uuid);
CREATE OR REPLACE FUNCTION public.get_user_role(_user_id uuid)
RETURNS app_role
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT role
  FROM user_roles
  WHERE user_id = _user_id
  ORDER BY 
    CASE 
      WHEN role = 'admin' THEN 1
      WHEN role = 'moderator' THEN 2
      WHEN role = 'user' THEN 3
    END
  LIMIT 1;
$$;

-- Fix has_role function
DROP FUNCTION IF EXISTS public.has_role(uuid, app_role);
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM user_roles
    WHERE user_id = _user_id
      AND role = _role
  );
$$;

-- Fix generate_str_wallet_address function (if it exists)
CREATE OR REPLACE FUNCTION public.generate_str_wallet_address()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN 'str_' || substr(md5(random()::text || clock_timestamp()::text), 1, 34);
END;
$$;

-- Fix get_client_ip function
DROP FUNCTION IF EXISTS public.get_client_ip();
CREATE OR REPLACE FUNCTION public.get_client_ip()
RETURNS inet
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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

-- Fix hash_password function (if it exists)
CREATE OR REPLACE FUNCTION public.hash_password(password_text text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Use bcrypt for secure password hashing
  RETURN extensions.crypt(password_text, extensions.gen_salt('bf', 8));
END;
$$;

-- Fix verify_password function
DROP FUNCTION IF EXISTS public.verify_password(text, text);
CREATE OR REPLACE FUNCTION public.verify_password(input_password text, stored_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Handle null inputs
  IF input_password IS NULL OR stored_hash IS NULL THEN
    RETURN false;
  END IF;
  
  -- Check if hash starts with bcrypt signature
  IF stored_hash LIKE '$2a$%' OR stored_hash LIKE '$2b$%' OR stored_hash LIKE '$2x$%' OR stored_hash LIKE '$2y$%' THEN
    RETURN (extensions.crypt(input_password, stored_hash) = stored_hash);
  END IF;
  
  -- Legacy plain text comparison (should be migrated)
  RETURN stored_hash = input_password;
END;
$$;

-- Fix sanitize_text_input function  
DROP FUNCTION IF EXISTS public.sanitize_text_input(text);
CREATE OR REPLACE FUNCTION public.sanitize_text_input(input_text text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Handle null input
  IF input_text IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Remove potential XSS and SQL injection attempts
  input_text := regexp_replace(input_text, '<[^>]*>', '', 'g');
  input_text := regexp_replace(input_text, '[''";]', '', 'g');
  
  -- Limit length
  IF length(input_text) > 1000 THEN
    input_text := left(input_text, 1000);
  END IF;
  
  RETURN trim(input_text);
END;
$$;