-- Create table to store support ticket fix history
CREATE TABLE public.support_ticket_fix_history (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  ticket_id uuid NOT NULL REFERENCES member_support_tickets(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  admin_id uuid,
  issue_type text NOT NULL,
  fix_attempted_at timestamp with time zone NOT NULL DEFAULT now(),
  fix_completed_at timestamp with time zone,
  success boolean NOT NULL DEFAULT false,
  
  -- Before state snapshot
  before_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  
  -- After state snapshot  
  after_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  
  -- Fix results and actions taken
  actions_taken jsonb NOT NULL DEFAULT '[]'::jsonb,
  error_message text,
  
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.support_ticket_fix_history ENABLE ROW LEVEL SECURITY;

-- Admins can view all fix history
CREATE POLICY "Admins can view all fix history"
  ON public.support_ticket_fix_history
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = auth.uid() 
    AND user_roles.role = 'admin'
  ));

-- Service role can manage fix history
CREATE POLICY "Service role can manage fix history"
  ON public.support_ticket_fix_history
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- Create index for faster queries
CREATE INDEX idx_fix_history_ticket_id ON public.support_ticket_fix_history(ticket_id);
CREATE INDEX idx_fix_history_user_id ON public.support_ticket_fix_history(user_id);