-- Business domain applications table
CREATE TABLE public.business_domain_applications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  personal_domain_id UUID NOT NULL,
  business_name TEXT NOT NULL,
  requested_domain TEXT NOT NULL,
  business_type TEXT NOT NULL DEFAULT 'company',
  registration_number TEXT,
  tax_id TEXT,
  business_address JSONB,
  industry TEXT,
  website_url TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT business_domain_status_check CHECK (status IN ('pending', 'under_review', 'approved', 'rejected', 'minted'))
);

-- Business domains table (after approval/minting)
CREATE TABLE public.business_domains (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  application_id UUID NOT NULL REFERENCES public.business_domain_applications(id),
  personal_domain_id UUID NOT NULL,
  domain_name TEXT NOT NULL UNIQUE,
  business_name TEXT NOT NULL,
  business_type TEXT NOT NULL,
  registration_number TEXT,
  tax_id TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  minted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Merchant account applications table
CREATE TABLE public.merchant_account_applications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  business_domain_id UUID NOT NULL REFERENCES public.business_domains(id),
  personal_banking_id UUID NOT NULL,
  business_name TEXT NOT NULL,
  business_description TEXT,
  expected_monthly_volume TEXT,
  average_transaction_size TEXT,
  products_services TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  requested_products JSONB DEFAULT '{"multi_currency_iban": true, "payment_processing": true}'::jsonb,
  admin_notes TEXT,
  processed_by UUID,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT merchant_status_check CHECK (status IN ('pending', 'under_review', 'approved', 'rejected'))
);

-- Merchant accounts table (after approval)
CREATE TABLE public.merchant_accounts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  business_domain_id UUID NOT NULL REFERENCES public.business_domains(id),
  application_id UUID NOT NULL REFERENCES public.merchant_account_applications(id),
  merchant_id TEXT NOT NULL UNIQUE,
  business_name TEXT NOT NULL,
  eur_iban_id UUID,
  chf_iban_id UUID,
  gbp_iban_id UUID,
  usd_iban_id UUID,
  payment_processing_enabled BOOLEAN DEFAULT false,
  api_key_hash TEXT,
  webhook_url TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.business_domain_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_account_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_accounts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for business_domain_applications
CREATE POLICY "Users can view their own business domain applications"
  ON public.business_domain_applications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own business domain applications"
  ON public.business_domain_applications FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all business domain applications"
  ON public.business_domain_applications FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can update business domain applications"
  ON public.business_domain_applications FOR UPDATE
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- RLS Policies for business_domains
CREATE POLICY "Users can view their own business domains"
  ON public.business_domains FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage business domains"
  ON public.business_domains FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- RLS Policies for merchant_account_applications
CREATE POLICY "Users can view their own merchant applications"
  ON public.merchant_account_applications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own merchant applications"
  ON public.merchant_account_applications FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all merchant applications"
  ON public.merchant_account_applications FOR SELECT
  USING (is_admin(auth.uid()));

CREATE POLICY "Admins can update merchant applications"
  ON public.merchant_account_applications FOR UPDATE
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));

-- RLS Policies for merchant_accounts
CREATE POLICY "Users can view their own merchant accounts"
  ON public.merchant_accounts FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage merchant accounts"
  ON public.merchant_accounts FOR ALL
  USING (is_admin(auth.uid()))
  WITH CHECK (is_admin(auth.uid()));