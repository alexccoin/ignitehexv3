-- Add reply and moderation fields to chat_messages
ALTER TABLE public.chat_messages
ADD COLUMN IF NOT EXISTS reply_to_id uuid NULL REFERENCES public.chat_messages(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS deleted_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL,
ADD COLUMN IF NOT EXISTS moderated_reason text NULL;

-- Improve realtime payload completeness for UPDATE/DELETE events
ALTER TABLE public.chat_messages REPLICA IDENTITY FULL;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_chat_messages_room_created ON public.chat_messages (room_type, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_reply_to ON public.chat_messages (reply_to_id);

-- Create chat_bans table
CREATE TABLE IF NOT EXISTS public.chat_bans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  room_type text NOT NULL,
  reason text,
  banned_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS and policies for chat_bans (admin only)
ALTER TABLE public.chat_bans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_all_chat_bans" ON public.chat_bans;
CREATE POLICY "admin_all_chat_bans"
ON public.chat_bans
FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Ensure RLS and policies on chat_messages for public read, user insert, admin update
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
-- Public can read messages (messages are public chats)
DROP POLICY IF EXISTS "public_can_read_chat" ON public.chat_messages;
CREATE POLICY "public_can_read_chat"
ON public.chat_messages
FOR SELECT
USING (true);

-- Users can insert their own messages
DROP POLICY IF EXISTS "users_can_insert_own_messages" ON public.chat_messages;
CREATE POLICY "users_can_insert_own_messages"
ON public.chat_messages
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can update any message (for moderation)
DROP POLICY IF EXISTS "admins_can_update_any_message" ON public.chat_messages;
CREATE POLICY "admins_can_update_any_message"
ON public.chat_messages
FOR UPDATE
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Create or replace send_chat_message with ban check and optional reply_to_id
CREATE OR REPLACE FUNCTION public.send_chat_message(message_text text, room_type text, reply_to_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  uid uuid;
  uname text;
  sanitized text;
  is_banned boolean;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Check ban (room-specific or global 'all')
  SELECT EXISTS (
    SELECT 1 FROM public.chat_bans b
    WHERE b.user_id = uid
      AND (b.room_type = room_type OR b.room_type = 'all')
      AND (b.expires_at IS NULL OR b.expires_at > now())
  ) INTO is_banned;

  IF is_banned THEN
    RAISE EXCEPTION 'You are banned from this chat room';
  END IF;

  -- Sanitize input and fetch username
  sanitized := sanitize_text_input(COALESCE(message_text, ''));
  IF length(trim(sanitized)) = 0 THEN
    RAISE EXCEPTION 'Message cannot be empty';
  END IF;

  SELECT COALESCE(up.str_domain_owned, 'Anonymous User')
  INTO uname
  FROM public.user_profiles up
  WHERE up.user_id = uid;

  INSERT INTO public.chat_messages (user_id, username, message, room_type, reply_to_id)
  VALUES (uid, COALESCE(uname, 'Anonymous User'), sanitized, room_type, reply_to_id);
END;
$$;

-- Admin: delete (soft-delete) a message
CREATE OR REPLACE FUNCTION public.admin_delete_chat_message(message_id uuid, reason text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin only.';
  END IF;

  UPDATE public.chat_messages
  SET is_deleted = true,
      deleted_by = auth.uid(),
      deleted_at = now(),
      moderated_reason = reason,
      updated_at = now()
  WHERE id = message_id;

  RETURN FOUND;
END;
$$;

-- Admin: ban a user (optionally until expires_at)
CREATE OR REPLACE FUNCTION public.admin_ban_user(target_user_id uuid, room_type text, reason text DEFAULT NULL, duration_minutes integer DEFAULT NULL)
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

-- Admin: unban by ban id
CREATE OR REPLACE FUNCTION public.admin_unban_user(ban_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied. Admin only.';
  END IF;

  DELETE FROM public.chat_bans WHERE id = ban_id;
  RETURN FOUND;
END;
$$;