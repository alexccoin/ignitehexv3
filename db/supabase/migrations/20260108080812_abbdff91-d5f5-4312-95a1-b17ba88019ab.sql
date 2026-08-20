
-- =============================================
-- SECURITY FIX: Protect PII and Financial Data
-- ONLY RLS policies - NO data/structure changes
-- =============================================

-- 1. Protect user_profiles - contains PII
-- First check if RLS is enabled, enable if not
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Drop any overly permissive policies
DROP POLICY IF EXISTS "Anyone can view profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.user_profiles;
DROP POLICY IF EXISTS "Profiles are viewable by everyone" ON public.user_profiles;

-- Users can only view their own profile
CREATE POLICY "Users can view own profile"
ON public.user_profiles
FOR SELECT
USING (auth.uid() = user_id);

-- Admins can view all profiles
CREATE POLICY "Admins can view all profiles"
ON public.user_profiles
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
);

-- 2. Protect user_personal_data_encrypted
ALTER TABLE public.user_personal_data_encrypted ENABLE ROW LEVEL SECURITY;

-- Drop any overly permissive policies
DROP POLICY IF EXISTS "Anyone can view encrypted data" ON public.user_personal_data_encrypted;
DROP POLICY IF EXISTS "Public can view encrypted data" ON public.user_personal_data_encrypted;

-- Users can only view their own encrypted data
CREATE POLICY "Users can view own encrypted data"
ON public.user_personal_data_encrypted
FOR SELECT
USING (auth.uid() = user_id);

-- Users can manage their own encrypted data
CREATE POLICY "Users can manage own encrypted data"
ON public.user_personal_data_encrypted
FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Admins can view all encrypted data
CREATE POLICY "Admins can view all encrypted data"
ON public.user_personal_data_encrypted
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
);

-- 3. Protect iban_accounts - contains banking details
ALTER TABLE public.iban_accounts ENABLE ROW LEVEL SECURITY;

-- Drop any overly permissive policies
DROP POLICY IF EXISTS "Anyone can view iban accounts" ON public.iban_accounts;
DROP POLICY IF EXISTS "Public can view iban accounts" ON public.iban_accounts;

-- Users can only view their own IBAN accounts
CREATE POLICY "Users can view own iban accounts"
ON public.iban_accounts
FOR SELECT
USING (auth.uid() = user_id);

-- Users can manage their own IBAN accounts
CREATE POLICY "Users can manage own iban accounts"
ON public.iban_accounts
FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Admins can view and manage all IBAN accounts
CREATE POLICY "Admins can manage all iban accounts"
ON public.iban_accounts
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
);
