-- Fix send_chat_message function to populate username field
CREATE OR REPLACE FUNCTION send_chat_message(
  message_text TEXT,
  room_type TEXT,
  reply_to_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id UUID;
  user_name TEXT;
BEGIN
  -- Get current user
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get username from user profile, fallback to email if not available
  SELECT 
    COALESCE(
      NULLIF(up.str_domain_username, ''), 
      NULLIF(up.full_name, ''), 
      au.email,
      'Anonymous User'
    )
  INTO user_name
  FROM auth.users au
  LEFT JOIN public.user_profiles up ON au.id = up.user_id
  WHERE au.id = current_user_id;

  -- Insert the message with username
  INSERT INTO public.chat_messages (
    user_id,
    username,
    message,
    room_type,
    reply_to_id,
    created_at,
    updated_at
  ) VALUES (
    current_user_id,
    user_name,
    message_text,
    send_chat_message.room_type,
    reply_to_id,
    NOW(),
    NOW()
  );
END;
$$;