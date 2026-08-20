-- Create business_profiles table connected to user profiles
CREATE TABLE IF NOT EXISTS public.business_profiles (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    personal_domain_id UUID NOT NULL,
    business_domain_application_id UUID REFERENCES public.business_domain_applications(id),
    business_domain_id UUID REFERENCES public.business_domains(id),
    
    -- Business ownership
    ownership_type TEXT NOT NULL DEFAULT 'owner' CHECK (ownership_type IN ('owner', 'power_of_attorney', 'authorized_representative')),
    power_of_attorney_document_url TEXT,
    
    -- Business identity
    business_legal_name TEXT NOT NULL,
    trading_name TEXT,
    business_domain_name TEXT,
    
    -- Registration details
    country_of_incorporation TEXT NOT NULL,
    registration_number TEXT,
    tax_id TEXT,
    vat_number TEXT,
    date_of_incorporation DATE,
    
    -- Contact information
    business_email TEXT NOT NULL,
    business_phone TEXT NOT NULL,
    website_url TEXT,
    
    -- Address
    street_address TEXT NOT NULL,
    address_line_2 TEXT,
    city TEXT NOT NULL,
    state_province TEXT,
    postal_code TEXT NOT NULL,
    country TEXT NOT NULL,
    
    -- Business type
    business_type TEXT NOT NULL DEFAULT 'company',
    industry TEXT,
    business_description TEXT,
    
    -- Status and verification
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected', 'suspended')),
    verified_at TIMESTAMPTZ,
    verified_by UUID,
    admin_notes TEXT,
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    CONSTRAINT unique_user_business_domain UNIQUE (user_id, business_domain_name)
);

-- Enable RLS
ALTER TABLE public.business_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own business profiles"
    ON public.business_profiles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own business profiles"
    ON public.business_profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own pending business profiles"
    ON public.business_profiles FOR UPDATE
    USING (auth.uid() = user_id AND status = 'pending');

CREATE POLICY "Admins can view all business profiles"
    ON public.business_profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'admin'
        )
    );

CREATE POLICY "Admins can update all business profiles"
    ON public.business_profiles FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'admin'
        )
    );

-- Add columns to business_domain_applications for enhanced form
ALTER TABLE public.business_domain_applications 
ADD COLUMN IF NOT EXISTS ownership_type TEXT DEFAULT 'owner',
ADD COLUMN IF NOT EXISTS power_of_attorney_document_url TEXT,
ADD COLUMN IF NOT EXISTS business_email TEXT,
ADD COLUMN IF NOT EXISTS business_phone TEXT,
ADD COLUMN IF NOT EXISTS business_description TEXT,
ADD COLUMN IF NOT EXISTS trading_name TEXT,
ADD COLUMN IF NOT EXISTS state_province TEXT,
ADD COLUMN IF NOT EXISTS date_of_incorporation DATE,
ADD COLUMN IF NOT EXISTS vat_number TEXT;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_business_profiles_user_id ON public.business_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_business_profiles_status ON public.business_profiles(status);

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION public.update_business_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

CREATE TRIGGER update_business_profiles_updated_at
    BEFORE UPDATE ON public.business_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_business_profiles_updated_at();