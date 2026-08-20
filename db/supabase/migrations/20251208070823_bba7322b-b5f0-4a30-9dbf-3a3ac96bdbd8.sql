-- Create CCoin Card Applications table
CREATE TABLE public.ccoin_card_applications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  str_domain_id UUID NOT NULL,
  str_domain_name TEXT NOT NULL,
  wallet_address TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  processed_at TIMESTAMP WITH TIME ZONE,
  processed_by UUID,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT ccoin_card_applications_status_check CHECK (status IN ('pending', 'approved', 'rejected'))
);

-- Enable RLS
ALTER TABLE public.ccoin_card_applications ENABLE ROW LEVEL SECURITY;

-- Users can view their own applications
CREATE POLICY "Users can view their own CCoin card applications"
ON public.ccoin_card_applications
FOR SELECT
USING (auth.uid() = user_id);

-- Users can create their own applications
CREATE POLICY "Users can create their own CCoin card applications"
ON public.ccoin_card_applications
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Admins can view all applications
CREATE POLICY "Admins can view all CCoin card applications"
ON public.ccoin_card_applications
FOR SELECT
USING (is_admin(auth.uid()));

-- Admins can update applications
CREATE POLICY "Admins can update CCoin card applications"
ON public.ccoin_card_applications
FOR UPDATE
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Create index for faster lookups
CREATE INDEX idx_ccoin_card_applications_user_id ON public.ccoin_card_applications(user_id);
CREATE INDEX idx_ccoin_card_applications_status ON public.ccoin_card_applications(status);