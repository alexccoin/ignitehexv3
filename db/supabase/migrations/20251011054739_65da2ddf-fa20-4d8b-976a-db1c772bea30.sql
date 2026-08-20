-- Create ARX applications table for membership onboarding
CREATE TABLE IF NOT EXISTS public.arx_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  location_data JSONB,
  ip_address INET,
  nda_accepted_at TIMESTAMP WITH TIME ZONE,
  gdpr_accepted_at TIMESTAMP WITH TIME ZONE,
  charter_accepted_at TIMESTAMP WITH TIME ZONE,
  application_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'declined')),
  processed_by UUID,
  processed_at TIMESTAMP WITH TIME ZONE,
  admin_notes TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.arx_applications ENABLE ROW LEVEL SECURITY;

-- Users can insert their own applications
CREATE POLICY "Users can submit their own ARX application"
ON public.arx_applications
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Users can view their own applications
CREATE POLICY "Users can view their own ARX application"
ON public.arx_applications
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Admins and ARX role can view all applications
CREATE POLICY "Admins and ARX can view all applications"
ON public.arx_applications
FOR SELECT
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role) OR 
  has_role(auth.uid(), 'arx'::app_role)
);

-- Admins can update applications
CREATE POLICY "Admins can update ARX applications"
ON public.arx_applications
FOR UPDATE
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_arx_applications_user_id ON public.arx_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_arx_applications_status ON public.arx_applications(status);

-- Add trigger for updated_at
CREATE OR REPLACE FUNCTION update_arx_applications_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_arx_applications_timestamp ON public.arx_applications;
CREATE TRIGGER update_arx_applications_timestamp
BEFORE UPDATE ON public.arx_applications
FOR EACH ROW
EXECUTE FUNCTION update_arx_applications_updated_at();