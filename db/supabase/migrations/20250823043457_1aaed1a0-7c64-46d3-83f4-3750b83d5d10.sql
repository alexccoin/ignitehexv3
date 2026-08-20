-- Fix ambiguous column reference in send_chat_message function
CREATE OR REPLACE FUNCTION send_chat_message(
  message_text TEXT,
  room_type TEXT,
  reply_to_id UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_user_id UUID;
BEGIN
  -- Get current user
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Insert the message with explicit table reference
  INSERT INTO public.chat_messages (
    user_id,
    message,
    room_type,
    reply_to_id,
    created_at,
    updated_at
  ) VALUES (
    current_user_id,
    message_text,
    send_chat_message.room_type,  -- Explicitly reference the parameter
    reply_to_id,
    NOW(),
    NOW()
  );
END;
$$;