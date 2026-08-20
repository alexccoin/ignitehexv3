-- Create the seed_str_applications table for STR-backed seed investments
CREATE TABLE public.seed_str_applications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  investment_amount NUMERIC NOT NULL DEFAULT 0,
  investment_currency TEXT NOT NULL DEFAULT 'STR',
  investment_tier TEXT NOT NULL DEFAULT 'standard',
  str_backing_amount NUMERIC NOT NULL DEFAULT 0,
  expected_return_rate NUMERIC NOT NULL DEFAULT 0,
  lock_period_months INTEGER NOT NULL DEFAULT 12,
  terms_accepted BOOLEAN NOT NULL DEFAULT false,
  terms_accepted_at TIMESTAMPTZ,
  nda_accepted BOOLEAN NOT NULL DEFAULT false,
  nda_accepted_at TIMESTAMPTZ,
  gdpr_accepted BOOLEAN NOT NULL DEFAULT false,
  gdpr_accepted_at TIMESTAMPTZ,
  risk_disclosure_accepted BOOLEAN NOT NULL DEFAULT false,
  risk_disclosure_accepted_at TIMESTAMPTZ,
  application_date TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMPTZ,
  credited_amount NUMERIC DEFAULT 0,
  credited_at TIMESTAMPTZ,
  suspended_at TIMESTAMPTZ,
  suspended_by UUID,
  suspension_reason TEXT,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create seed_str_audit_log for comprehensive audit trail
CREATE TABLE public.seed_str_audit_log (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  application_id UUID REFERENCES public.seed_str_applications(id),
  user_id UUID NOT NULL,
  action_type TEXT NOT NULL,
  action_details JSONB,
  performed_by UUID NOT NULL,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Create seed_str_backups for admin backup functionality
CREATE TABLE public.seed_str_backups (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  backup_name TEXT NOT NULL,
  backup_type TEXT NOT NULL DEFAULT 'full',
  total_applications INTEGER NOT NULL DEFAULT 0,
  total_investment_value NUMERIC NOT NULL DEFAULT 0,
  backup_data JSONB NOT NULL,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.seed_str_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seed_str_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seed_str_backups ENABLE ROW LEVEL SECURITY;

-- Create policies for seed_str_applications
CREATE POLICY "Users can view their own seed applications"
ON public.seed_str_applications FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own seed applications"
ON public.seed_str_applications FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all seed applications"
ON public.seed_str_applications FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "Admins can update seed applications"
ON public.seed_str_applications FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Create policies for seed_str_audit_log
CREATE POLICY "Admins can view seed audit logs"
ON public.seed_str_audit_log FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "System can insert seed audit logs"
ON public.seed_str_audit_log FOR INSERT
TO anon, authenticated
WITH CHECK (true);

-- Create policies for seed_str_backups
CREATE POLICY "Admins can manage seed backups"
ON public.seed_str_backups FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Create indexes for performance
CREATE INDEX idx_seed_str_applications_user_id ON public.seed_str_applications(user_id);
CREATE INDEX idx_seed_str_applications_status ON public.seed_str_applications(status);
CREATE INDEX idx_seed_str_applications_date ON public.seed_str_applications(application_date DESC);
CREATE INDEX idx_seed_str_audit_log_application ON public.seed_str_audit_log(application_id);
CREATE INDEX idx_seed_str_audit_log_user ON public.seed_str_audit_log(user_id);

-- Create updated_at trigger
CREATE TRIGGER update_seed_str_applications_updated_at
BEFORE UPDATE ON public.seed_str_applications
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();