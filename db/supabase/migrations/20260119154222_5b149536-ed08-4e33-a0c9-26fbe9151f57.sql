-- Create table for private Seed STR applications
CREATE TABLE IF NOT EXISTS public.private_seed_str_applications (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    investment_amount NUMERIC NOT NULL DEFAULT 0,
    investment_tier TEXT,
    str_backing_amount NUMERIC DEFAULT 0,
    expected_return_rate NUMERIC DEFAULT 0,
    lock_period_months INTEGER DEFAULT 12,
    terms_accepted BOOLEAN DEFAULT FALSE,
    terms_accepted_at TIMESTAMPTZ,
    nda_accepted BOOLEAN DEFAULT FALSE,
    nda_accepted_at TIMESTAMPTZ,
    gdpr_accepted BOOLEAN DEFAULT FALSE,
    gdpr_accepted_at TIMESTAMPTZ,
    risk_disclosure_accepted BOOLEAN DEFAULT FALSE,
    risk_disclosure_accepted_at TIMESTAMPTZ,
    status TEXT DEFAULT 'pending',
    payment_status TEXT DEFAULT 'awaiting_payment',
    payment_deadline TIMESTAMPTZ,
    payment_submitted_at TIMESTAMPTZ,
    payment_crypto TEXT,
    payment_amount NUMERIC,
    payment_hash TEXT,
    str_shares_credited NUMERIC DEFAULT 0,
    credited_amount NUMERIC DEFAULT 0,
    credited_at TIMESTAMPTZ,
    admin_notes TEXT,
    processed_at TIMESTAMPTZ,
    processed_by UUID,
    suspended_at TIMESTAMPTZ,
    suspended_by UUID,
    suspension_reason TEXT,
    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID,
    application_date TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}',
    ip_address INET DEFAULT '0.0.0.0',
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create audit log for private seed str
CREATE TABLE IF NOT EXISTS public.private_seed_str_audit_log (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    application_id UUID REFERENCES public.private_seed_str_applications(id),
    user_id UUID NOT NULL,
    action_type TEXT NOT NULL,
    action_details JSONB DEFAULT '{}',
    performed_by UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.private_seed_str_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.private_seed_str_audit_log ENABLE ROW LEVEL SECURITY;

-- RLS policies for private_seed_str_applications
CREATE POLICY "Users can view own private seed str applications"
ON public.private_seed_str_applications FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can create own private seed str applications"
ON public.private_seed_str_applications FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own private seed str applications"
ON public.private_seed_str_applications FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all private seed str applications"
ON public.private_seed_str_applications FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update all private seed str applications"
ON public.private_seed_str_applications FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- RLS policies for audit log
CREATE POLICY "Admins can view private seed str audit logs"
ON public.private_seed_str_audit_log FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Authenticated users can insert private seed str audit logs"
ON public.private_seed_str_audit_log FOR INSERT
TO authenticated
WITH CHECK (true);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_private_seed_str_apps_user_id ON public.private_seed_str_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_private_seed_str_apps_status ON public.private_seed_str_applications(status);
CREATE INDEX IF NOT EXISTS idx_private_seed_str_audit_app_id ON public.private_seed_str_audit_log(application_id);