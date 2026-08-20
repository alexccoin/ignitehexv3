-- Fix all remaining functions with mutable search paths that are SECURITY DEFINER
-- These functions need to be dropped and recreated with proper search_path

DROP FUNCTION IF EXISTS public.admin_ban_user(uuid, text, text, integer);
CREATE OR REPLACE FUNCTION public.admin_ban_user(target_user_id uuid, room_type text, reason text, duration_minutes integer DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  until_time timestamptz;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin only.';
  END IF;

  IF duration_minutes IS NOT NULL THEN
    until_time := now() + make_interval(mins => duration_minutes);
  ELSE
    until_time := NULL;
  END IF;

  INSERT INTO public.chat_bans (user_id, room_type, reason, banned_by, expires_at)
  VALUES (target_user_id, room_type, reason, auth.uid(), until_time);

  RETURN TRUE;
END;
$$;

-- Fix remaining security definer functions one by one to avoid long migration
DROP FUNCTION IF EXISTS public.sanitize_text_input(text);
CREATE OR REPLACE FUNCTION public.sanitize_text_input(input_text text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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