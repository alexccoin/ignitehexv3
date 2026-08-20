-- Remove overly permissive public read policy on chat_messages
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'chat_messages' AND policyname = 'public_can_read_chat'
  ) THEN
    DROP POLICY "public_can_read_chat" ON public.chat_messages;
  END IF;
END $$;

-- Ensure an authenticated-only read policy exists for public room (leave existing secure policy as is)
-- If such a policy didn't exist, create a conservative one
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'chat_messages' AND policyname = 'authenticated_can_read_public_chat'
  ) THEN
    CREATE POLICY "authenticated_can_read_public_chat"
    ON public.chat_messages
    FOR SELECT
    TO authenticated
    USING (
      auth.uid() IS NOT NULL AND room_type = 'public'
    );
  END IF;
END $$;