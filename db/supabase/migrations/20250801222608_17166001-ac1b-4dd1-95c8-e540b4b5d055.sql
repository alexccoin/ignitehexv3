-- Add room_type column to chat_messages
ALTER TABLE public.chat_messages ADD COLUMN room_type text NOT NULL DEFAULT 'public';

-- Create token_transfers table
CREATE TABLE public.token_transfers (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id uuid NOT NULL,
  recipient_id uuid NOT NULL, 
  token_type text NOT NULL,
  amount numeric NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  notes text,
  transaction_hash text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  processed_at timestamp with time zone,
  processed_by uuid
);

-- Enable RLS on token_transfers
ALTER TABLE public.token_transfers ENABLE ROW LEVEL SECURITY;

-- Create policies for token_transfers
CREATE POLICY "Users can create their own transfers" 
ON public.token_transfers 
FOR INSERT 
WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can view their own transfers" 
ON public.token_transfers 
FOR SELECT 
USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Admins can manage all transfers" 
ON public.token_transfers 
FOR ALL 
USING (is_admin(auth.uid()));

-- Update send_chat_message function to support room types
CREATE OR REPLACE FUNCTION public.send_chat_message(message_text text, room_type text DEFAULT 'public')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  user_domain text;
  message_id uuid;
  current_user_role app_role;
BEGIN
  -- Get current user
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Get user role
  SELECT get_user_role(auth.uid()) INTO current_user_role;
  
  -- Check room access permissions
  IF room_type = 'admin' AND current_user_role != 'admin' THEN
    RAISE EXCEPTION 'Admin access required for admin room';
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
  INSERT INTO chat_messages (user_id, username, message, room_type)
  VALUES (auth.uid(), user_domain, message_text, room_type)
  RETURNING id INTO message_id;

  RETURN message_id;
END;
$$;