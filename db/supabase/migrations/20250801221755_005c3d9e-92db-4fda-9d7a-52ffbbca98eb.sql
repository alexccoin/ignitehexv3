-- Enable realtime for chat_messages
ALTER TABLE public.chat_messages REPLICA IDENTITY FULL;

-- Add chat_messages to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;