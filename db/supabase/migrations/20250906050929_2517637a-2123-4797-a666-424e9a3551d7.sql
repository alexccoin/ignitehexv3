-- Fix remaining security function with mutable search path
DROP FUNCTION IF EXISTS public.sanitize_chat_message(text);
CREATE OR REPLACE FUNCTION public.sanitize_chat_message(message_text text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Handle null input
  IF message_text IS NULL THEN
    RETURN NULL;
  END IF;
  
  -- Basic sanitization for chat messages
  message_text := trim(message_text);
  
  -- Remove potentially harmful content
  message_text := regexp_replace(message_text, '<[^>]*>', '', 'g');
  message_text := regexp_replace(message_text, '[''";]', '', 'g');
  
  -- Limit message length
  IF length(message_text) > 500 THEN
    message_text := left(message_text, 500) || '...';
  END IF;
  
  RETURN message_text;
END;
$$;

-- Fix any other potential remaining functions with security definer but no search path
DROP FUNCTION IF EXISTS public.admin_unban_user(uuid, text);
CREATE OR REPLACE FUNCTION public.admin_unban_user(target_user_id uuid, room_type text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin only.';
  END IF;

  DELETE FROM public.chat_bans 
  WHERE user_id = target_user_id AND room_type = admin_unban_user.room_type;

  RETURN TRUE;
END;
$$;