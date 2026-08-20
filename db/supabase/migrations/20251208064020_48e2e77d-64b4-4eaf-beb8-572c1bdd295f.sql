-- Create visa_card_applications table
CREATE TABLE public.visa_card_applications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  card_type TEXT NOT NULL CHECK (card_type IN ('virtual', 'physical')),
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  str_domain TEXT,
  wallet_address TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'on_hold')),
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.visa_card_applications ENABLE ROW LEVEL SECURITY;

-- Users can view their own applications
CREATE POLICY "Users can view their own visa applications"
ON public.visa_card_applications
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own applications
CREATE POLICY "Users can create their own visa applications"
ON public.visa_card_applications
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all applications
CREATE POLICY "Admins can view all visa applications"
ON public.visa_card_applications
FOR SELECT
USING (EXISTS (
  SELECT 1 FROM user_roles 
  WHERE user_roles.user_id = auth.uid() 
  AND user_roles.role = 'admin'
));

-- Admins can update applications
CREATE POLICY "Admins can update visa applications"
ON public.visa_card_applications
FOR UPDATE
USING (EXISTS (
  SELECT 1 FROM user_roles 
  WHERE user_roles.user_id = auth.uid() 
  AND user_roles.role = 'admin'
));

-- Create index for faster queries
CREATE INDEX idx_visa_card_applications_status ON public.visa_card_applications(status);
CREATE INDEX idx_visa_card_applications_user_id ON public.visa_card_applications(user_id);