-- Fix remaining functions with mutable search paths (without dropping dependencies)
-- This addresses the security linter warning: "Function Search Path Mutable"

-- Fix get_user_role function (replace without dropping)
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

-- Fix has_role function (replace without dropping - it has RLS policy dependencies)
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

-- Fix get_client_ip function (replace without dropping)
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

-- Fix verify_password function (replace without dropping)
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

-- Fix sanitize_text_input function (replace without dropping)
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