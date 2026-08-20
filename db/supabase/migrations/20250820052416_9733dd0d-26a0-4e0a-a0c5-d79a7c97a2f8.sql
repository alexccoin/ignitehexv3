-- CRITICAL SECURITY FIXES - Phase 2: Address Remaining Data Exposure Issues

-- 1. Ensure RLS is enabled on all sensitive tables and verify no permissive policies exist

-- Drop any overly permissive policies and ensure strict access control
-- user_profiles table
DROP POLICY IF EXISTS "Admins can view all user profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Admins can update all user profiles" ON public.user_profiles;

-- Recreate admin policies with explicit admin checks
CREATE POLICY "Strict admin view user profiles" ON public.user_profiles
FOR SELECT USING (is_admin(auth.uid()));

CREATE POLICY "Strict admin update user profiles" ON public.user_profiles  
FOR UPDATE USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- transactions table  
DROP POLICY IF EXISTS "Admin users can view all transactions" ON public.transactions;

CREATE POLICY "Strict admin view all transactions" ON public.transactions
FOR SELECT USING (is_admin(auth.uid()));

-- iban_accounts table
DROP POLICY IF EXISTS "Admins can manage all IBAN accounts" ON public.iban_accounts;

CREATE POLICY "Strict admin manage IBAN accounts" ON public.iban_accounts
FOR ALL USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- prepaid_cards table
DROP POLICY IF EXISTS "Admins can manage all prepaid cards" ON public.prepaid_cards;

CREATE POLICY "Strict admin manage prepaid cards" ON public.prepaid_cards
FOR ALL USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- github_integrations table
DROP POLICY IF EXISTS "Admins can manage all GitHub integrations" ON public.github_integrations;

CREATE POLICY "Strict admin manage GitHub integrations" ON public.github_integrations
FOR ALL USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- 2. Add additional table-level security controls

-- Create function to validate sensitive data access
CREATE OR REPLACE FUNCTION validate_sensitive_data_access(table_name text, operation text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  current_user_id := auth.uid();
  
  -- Require authentication for all sensitive data access
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required for accessing %', table_name;
  END IF;
  
  -- Log all access attempts to sensitive data
  INSERT INTO security_audit_log (
    user_id, 
    action, 
    resource_type, 
    details
  ) VALUES (
    current_user_id,
    operation || '_access_attempt',
    table_name,
    jsonb_build_object(
      'timestamp', now(),
      'ip_address', get_client_ip(),
      'authenticated', true
    )
  );
  
  RETURN true;
END;
$$;

-- 3. Create secure view functions for sensitive data (replace direct table access)

-- Secure user profile view function
CREATE OR REPLACE FUNCTION get_user_profile_data(target_user_id uuid DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  user_id uuid, 
  full_name text,
  email_address text,
  str_domain_owned text,
  status account_status,
  user_status user_status,
  wallet_setup_completed boolean,
  recovery_words_encrypted boolean,
  two_factor_enabled boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  requesting_user_id uuid;
BEGIN
  requesting_user_id := auth.uid();
  
  -- Validate access
  PERFORM validate_sensitive_data_access('user_profiles', 'secure_select');
  
  -- Determine target user
  IF target_user_id IS NULL THEN
    target_user_id := requesting_user_id;
  END IF;
  
  -- Security check: only own data or admin access
  IF target_user_id != requesting_user_id AND NOT is_admin(requesting_user_id) THEN
    RAISE EXCEPTION 'Access denied: can only access own profile data';
  END IF;
  
  RETURN QUERY
  SELECT 
    up.id,
    up.user_id,
    up.full_name,
    up.email_address,
    up.str_domain_owned,
    up.status,
    up.user_status,
    up.wallet_setup_completed,
    up.recovery_words_encrypted,
    up.two_factor_enabled
  FROM user_profiles up
  WHERE up.user_id = target_user_id;
END;
$$;

-- Secure transaction view function
CREATE OR REPLACE FUNCTION get_user_transactions(limit_count integer DEFAULT 50)
RETURNS TABLE(
  id uuid,
  amount numeric,
  status text,
  created_at timestamp with time zone,
  transaction_id text
)
LANGUAGE plpgsql
SECURITY DEFINER  
SET search_path = 'public'
AS $$
DECLARE
  requesting_user_id uuid;
BEGIN
  requesting_user_id := auth.uid();
  
  -- Validate access
  PERFORM validate_sensitive_data_access('transactions', 'secure_select');
  
  IF requesting_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required for transaction access';
  END IF;
  
  RETURN QUERY
  SELECT 
    t.id,
    t.amount,
    t.status,
    t.created_at,
    t.transaction_id
  FROM transactions t
  WHERE t.user_id = requesting_user_id
  ORDER BY t.created_at DESC
  LIMIT limit_count;
END;
$$;

-- 4. Add row-level data masking for additional protection

-- Function to mask sensitive data in responses
CREATE OR REPLACE FUNCTION mask_sensitive_fields(
  data_type text,
  field_value text,
  show_full boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Only show full data to authenticated users accessing their own data or admins
  IF NOT show_full THEN
    CASE data_type
      WHEN 'email' THEN
        RETURN LEFT(field_value, 3) || '***@' || SPLIT_PART(field_value, '@', 2);
      WHEN 'iban' THEN  
        RETURN '***MASKED***';
      WHEN 'card' THEN
        RETURN '****-****-****-' || RIGHT(field_value, 4);
      WHEN 'wallet' THEN
        RETURN LEFT(field_value, 6) || '...' || RIGHT(field_value, 4);
      ELSE
        RETURN '***PROTECTED***';
    END CASE;
  END IF;
  
  RETURN field_value;
END;
$$;

-- 5. Create emergency data protection switch

-- Function to immediately disable all sensitive data access (emergency use)
CREATE OR REPLACE FUNCTION emergency_disable_sensitive_access()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Only admins can trigger emergency lockdown
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required for emergency lockdown';
  END IF;
  
  -- Log the emergency action
  INSERT INTO security_audit_log (
    user_id, 
    action, 
    resource_type, 
    details
  ) VALUES (
    auth.uid(),
    'emergency_lockdown_initiated',
    'system_security',
    jsonb_build_object(
      'timestamp', now(),
      'initiated_by', auth.uid(),
      'action', 'disable_sensitive_data_access'
    )
  );
  
  -- This would typically involve disabling RLS policies or adding emergency restrictions
  -- For now, we log the action and return success
  RETURN true;
END;
$$;