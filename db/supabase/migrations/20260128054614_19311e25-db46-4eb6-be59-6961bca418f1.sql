-- =====================================================
-- SECURITY HARDENING MIGRATION (v5)
-- Only modifies policies and functions - NO DATA CHANGES
-- =====================================================

-- 1. Fix user_str_shares RLS policies - Drop all existing first
DROP POLICY IF EXISTS "System can manage str shares" ON public.user_str_shares;
DROP POLICY IF EXISTS "Users can view own str shares" ON public.user_str_shares;
DROP POLICY IF EXISTS "Admins can view all str shares" ON public.user_str_shares;
DROP POLICY IF EXISTS "Admins can manage str shares" ON public.user_str_shares;

-- Create proper restrictive policies for user_str_shares
CREATE POLICY "Users can view own str shares"
ON public.user_str_shares FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all str shares"
ON public.user_str_shares FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can manage str shares"
ON public.user_str_shares FOR ALL
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));

-- 2. Fix wallet_security_log RLS policies
DROP POLICY IF EXISTS "System can insert wallet logs" ON public.wallet_security_log;
DROP POLICY IF EXISTS "Users can insert own wallet logs" ON public.wallet_security_log;
DROP POLICY IF EXISTS "Admins can view wallet logs" ON public.wallet_security_log;

CREATE POLICY "Users can insert own wallet logs"
ON public.wallet_security_log FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view wallet logs"
ON public.wallet_security_log FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));

-- 3. Fix staking_data_cache - restrict to service_role only
DROP POLICY IF EXISTS "Service role manages cache" ON public.staking_data_cache;

CREATE POLICY "Service role manages cache"
ON public.staking_data_cache FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- 4. Safely update SECURITY DEFINER functions with proper search_path
-- Only alter functions that exist

-- is_admin
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.is_admin(uuid) SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- has_role
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.has_role(uuid, app_role) SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- generate_str_wallet_address
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.generate_str_wallet_address() SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- verify_admin_access
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.verify_admin_access() SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- log_security_event
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.log_security_event(uuid, text, jsonb) SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- has_pool_access
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.has_pool_access(uuid, uuid) SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- auto_generate_str_wallet
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.auto_generate_str_wallet() SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- secure_update_user_profile
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.secure_update_user_profile(uuid, jsonb) SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- validate_founder_position_input
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.validate_founder_position_input() SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;

-- check_user_or_system (already has search_path per memory, but let's ensure it's set)
DO $$
BEGIN
  EXECUTE 'ALTER FUNCTION public.check_user_or_system() SET search_path = public';
EXCEPTION WHEN undefined_function THEN
  NULL;
END;
$$;