-- Create CCoin Network Bank applications table
CREATE TABLE public.ccoin_bank_applications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  
  -- Legal agreements
  gdpr_accepted BOOLEAN NOT NULL DEFAULT false,
  gdpr_accepted_at TIMESTAMP WITH TIME ZONE,
  terms_accepted BOOLEAN NOT NULL DEFAULT false,
  terms_accepted_at TIMESTAMP WITH TIME ZONE,
  nda_accepted BOOLEAN NOT NULL DEFAULT false,
  nda_accepted_at TIMESTAMP WITH TIME ZONE,
  
  -- Signature
  signature_full_name TEXT NOT NULL,
  signature_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  
  -- Admin processing
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMP WITH TIME ZONE,
  admin_notes TEXT,
  
  -- Metadata
  ip_address INET,
  user_agent TEXT,
  application_metadata JSONB DEFAULT '{}'::jsonb,
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.ccoin_bank_applications ENABLE ROW LEVEL SECURITY;

-- Users can submit their own application
CREATE POLICY "Users can submit their own CCoin Bank application"
ON public.ccoin_bank_applications
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can view their own application
CREATE POLICY "Users can view their own CCoin Bank application"
ON public.ccoin_bank_applications
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can view all applications
CREATE POLICY "Admins can view all CCoin Bank applications"
ON public.ccoin_bank_applications
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
);

-- Admins can update applications
CREATE POLICY "Admins can update CCoin Bank applications"
ON public.ccoin_bank_applications
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'
  )
);

-- Create index for faster queries
CREATE INDEX idx_ccoin_bank_applications_user_id ON public.ccoin_bank_applications(user_id);
CREATE INDEX idx_ccoin_bank_applications_status ON public.ccoin_bank_applications(status);
CREATE INDEX idx_ccoin_bank_applications_created_at ON public.ccoin_bank_applications(created_at DESC);

-- Create updated_at trigger
CREATE TRIGGER update_ccoin_bank_applications_updated_at
BEFORE UPDATE ON public.ccoin_bank_applications
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();