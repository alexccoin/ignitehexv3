-- Create support tickets table for member error reports
CREATE TABLE public.member_support_tickets (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  user_email TEXT NOT NULL,
  user_phone TEXT,
  full_name TEXT,
  str_domain TEXT,
  category TEXT NOT NULL CHECK (category IN ('profile_security', 'voucher', 'staking', 'banking', 'other')),
  error_details TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'resolved', 'closed')),
  resolution_time_hours INTEGER DEFAULT 72,
  admin_notes TEXT,
  resolved_at TIMESTAMP WITH TIME ZONE,
  resolved_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.member_support_tickets ENABLE ROW LEVEL SECURITY;

-- Users can view their own tickets
CREATE POLICY "Users can view their own support tickets"
ON public.member_support_tickets
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own tickets
CREATE POLICY "Users can create their own support tickets"
ON public.member_support_tickets
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all tickets
CREATE POLICY "Admins can view all support tickets"
ON public.member_support_tickets
FOR SELECT
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role = 'admin'));

-- Admins can update tickets
CREATE POLICY "Admins can update support tickets"
ON public.member_support_tickets
FOR UPDATE
USING (EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role = 'admin'));

-- Create index for admin queries
CREATE INDEX idx_member_support_tickets_status ON public.member_support_tickets(status);
CREATE INDEX idx_member_support_tickets_category ON public.member_support_tickets(category);
CREATE INDEX idx_member_support_tickets_user_id ON public.member_support_tickets(user_id);

-- Trigger for updated_at
CREATE TRIGGER update_member_support_tickets_updated_at
BEFORE UPDATE ON public.member_support_tickets
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();