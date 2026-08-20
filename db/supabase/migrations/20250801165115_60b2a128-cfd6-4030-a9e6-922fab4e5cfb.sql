-- Create user_messages table for admin to user messaging
CREATE TABLE public.user_messages (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id UUID NOT NULL, -- Admin who sent the message
  recipient_id UUID NOT NULL, -- User who receives the message
  subject TEXT NOT NULL,
  message TEXT NOT NULL,
  message_type TEXT NOT NULL DEFAULT 'info', -- info, warning, success, error
  is_read BOOLEAN NOT NULL DEFAULT false,
  is_popup_shown BOOLEAN NOT NULL DEFAULT false, -- Track if popup was shown
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  read_at TIMESTAMP WITH TIME ZONE NULL
);

-- Enable RLS
ALTER TABLE public.user_messages ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Admins can manage all messages" 
ON public.user_messages 
FOR ALL 
USING (is_admin(auth.uid()));

CREATE POLICY "Users can view their own messages" 
ON public.user_messages 
FOR SELECT 
USING (auth.uid() = recipient_id);

CREATE POLICY "Users can update their own message read status" 
ON public.user_messages 
FOR UPDATE 
USING (auth.uid() = recipient_id)
WITH CHECK (auth.uid() = recipient_id);

-- Create function to update timestamps
CREATE TRIGGER update_user_messages_updated_at
BEFORE UPDATE ON public.user_messages
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();