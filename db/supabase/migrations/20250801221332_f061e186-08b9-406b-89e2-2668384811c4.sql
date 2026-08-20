-- Create chat messages table for public chat room
CREATE TABLE public.chat_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username text NOT NULL, -- Domain name from user profile
  message text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Create policies for public chat (everyone can read, authenticated users can create)
CREATE POLICY "Anyone can view chat messages" 
ON public.chat_messages 
FOR SELECT 
USING (true);

CREATE POLICY "Authenticated users can send messages" 
ON public.chat_messages 
FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Create policy to allow users to update their own messages
CREATE POLICY "Users can update their own messages" 
ON public.chat_messages 
FOR UPDATE 
USING (auth.uid() = user_id);

-- Create trigger for automatic timestamp updates
CREATE TRIGGER update_chat_messages_updated_at
BEFORE UPDATE ON public.chat_messages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Create function to send chat message with domain name as username
CREATE OR REPLACE FUNCTION public.send_chat_message(message_text text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_domain text;
  message_id uuid;
BEGIN
  -- Get current user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Get user's domain name from profile
  SELECT str_domain_owned INTO user_domain
  FROM user_profiles 
  WHERE user_id = auth.uid();

  -- Use domain name as username, fallback to 'Anonymous' if no domain
  IF user_domain IS NULL OR user_domain = '' THEN
    user_domain := 'Anonymous User';
  END IF;

  -- Insert the message
  INSERT INTO chat_messages (user_id, username, message)
  VALUES (auth.uid(), user_domain, message_text)
  RETURNING id INTO message_id;

  RETURN message_id;
END;
$$;