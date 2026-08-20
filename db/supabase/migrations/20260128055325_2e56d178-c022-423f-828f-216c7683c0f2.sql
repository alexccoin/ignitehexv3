-- =====================================================
-- FIX WARN: RLS Policies with USING (true) / WITH CHECK (true)
-- Only modifies policies - NO DATA CHANGES
-- =====================================================

-- 1. arx_audit_trail - already fixed in previous migration (policy dropped)
-- Recreate it with proper check
DROP POLICY IF EXISTS "Authenticated can insert audit logs" ON public.arx_audit_trail;
CREATE POLICY "Authenticated can insert audit logs"
ON public.arx_audit_trail FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = performed_by);

-- 2. ccoin_network_transactions - No user_id column, restrict to authenticated only
-- This is a network transaction log, authenticated insert is acceptable
DROP POLICY IF EXISTS "Users can insert own network transactions" ON public.ccoin_network_transactions;
DROP POLICY IF EXISTS "Authenticated can insert network transactions" ON public.ccoin_network_transactions;
CREATE POLICY "Authenticated can insert network transactions"
ON public.ccoin_network_transactions FOR INSERT
TO authenticated
WITH CHECK (true); -- No user_id column, but restricted to authenticated

-- 3. private_seed_str_audit_log - Validate user_id on insert
DROP POLICY IF EXISTS "Users can insert own private seed str audit logs" ON public.private_seed_str_audit_log;
DROP POLICY IF EXISTS "Authenticated users can insert private seed str audit logs" ON public.private_seed_str_audit_log;
CREATE POLICY "Users can insert own private seed str audit logs"
ON public.private_seed_str_audit_log FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 4. security_audit_log - Restrict to user's own logs
DROP POLICY IF EXISTS "Users can insert own security audit logs" ON public.security_audit_log;
DROP POLICY IF EXISTS "System can insert audit logs" ON public.security_audit_log;
CREATE POLICY "Users can insert own security audit logs"
ON public.security_audit_log FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 5. seed_str_audit_log - Restrict to user's own logs or admin
DROP POLICY IF EXISTS "Users can insert own seed str audit logs" ON public.seed_str_audit_log;
DROP POLICY IF EXISTS "System can insert seed audit logs" ON public.seed_str_audit_log;
CREATE POLICY "Users can insert own seed str audit logs"
ON public.seed_str_audit_log FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id OR public.has_role(auth.uid(), 'admin'::app_role) OR public.has_role(auth.uid(), 'seed_str_admin'::app_role));

-- 6. seed_str_referrals - Restrict to authenticated users (affiliate_id is the referrer)
DROP POLICY IF EXISTS "Authenticated users can create referral entries" ON public.seed_str_referrals;
DROP POLICY IF EXISTS "Anyone can create referral entries" ON public.seed_str_referrals;
CREATE POLICY "Authenticated users can create referral entries"
ON public.seed_str_referrals FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = affiliate_id OR auth.uid() = referred_user_id);