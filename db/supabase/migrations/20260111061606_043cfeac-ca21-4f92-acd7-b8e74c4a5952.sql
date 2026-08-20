-- =====================================================
-- SECURITY FIX: Tighten overly permissive RLS policies
-- This migration does NOT delete or modify any data
-- =====================================================

-- 1. FIX crypto_wallets - CRITICAL (currently anyone can read/write)
DROP POLICY IF EXISTS "System can manage crypto wallets" ON public.crypto_wallets;

CREATE POLICY "Users can view own crypto wallets"
ON public.crypto_wallets FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own crypto wallets"
ON public.crypto_wallets FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own crypto wallets"
ON public.crypto_wallets FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can manage all crypto wallets"
ON public.crypto_wallets FOR ALL
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

-- 2. FIX crypto_orders - Anyone can update (dangerous)
DROP POLICY IF EXISTS "System can update orders" ON public.crypto_orders;

CREATE POLICY "Users can update own orders"
ON public.crypto_orders FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can update all orders"
ON public.crypto_orders FOR UPDATE
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

-- 3. FIX fiat_transactions - uses from_user_id/to_user_id
DROP POLICY IF EXISTS "System can update fiat transactions" ON public.fiat_transactions;

CREATE POLICY "Users can update own fiat transactions"
ON public.fiat_transactions FOR UPDATE
TO authenticated
USING (auth.uid() = from_user_id OR auth.uid() = to_user_id)
WITH CHECK (auth.uid() = from_user_id OR auth.uid() = to_user_id);

CREATE POLICY "Admins can update all fiat transactions"
ON public.fiat_transactions FOR UPDATE
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

-- 4. Tighten INSERT policies

DROP POLICY IF EXISTS "System can insert auth attempts" ON public.auth_attempts;
CREATE POLICY "Authenticated can insert auth attempts"
ON public.auth_attempts FOR INSERT
TO authenticated
WITH CHECK (user_id IS NULL OR auth.uid() = user_id);

-- ccoin_network_transactions has no user_id - keep permissive but require auth
DROP POLICY IF EXISTS "System can insert transactions" ON public.ccoin_network_transactions;
CREATE POLICY "Authenticated can insert network transactions"
ON public.ccoin_network_transactions FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "System can insert ccoin validations" ON public.ccoin_validations;
CREATE POLICY "Authenticated can insert ccoin validations"
ON public.ccoin_validations FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can create transactions" ON public.domain_marketplace_transactions;
CREATE POLICY "Authenticated can create marketplace transactions"
ON public.domain_marketplace_transactions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id OR auth.uid() = seller_id);

-- pending_transfers_treasury uses from_user_id
DROP POLICY IF EXISTS "System can insert pending transfers" ON public.pending_transfers_treasury;
CREATE POLICY "Authenticated can insert pending transfers"
ON public.pending_transfers_treasury FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = from_user_id);

DROP POLICY IF EXISTS "System can insert profile changes" ON public.profile_changes;
CREATE POLICY "Authenticated can insert own profile changes"
ON public.profile_changes FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert STARW interaction history" ON public.starw_interaction_history;
CREATE POLICY "Authenticated can insert STARW history"
ON public.starw_interaction_history FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert transfer reports" ON public.transfer_reports;
CREATE POLICY "Authenticated can insert transfer reports"
ON public.transfer_reports FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert voucher errors" ON public.voucher_error_log;
CREATE POLICY "Authenticated can insert voucher errors"
ON public.voucher_error_log FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- voucher_redemption_history has no user_id - uses performed_by
DROP POLICY IF EXISTS "System can insert voucher history" ON public.voucher_redemption_history;
CREATE POLICY "Authenticated can insert voucher history"
ON public.voucher_redemption_history FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = performed_by);

DROP POLICY IF EXISTS "System can insert wallet logs" ON public.wallet_security_log;
CREATE POLICY "Authenticated can insert wallet logs"
ON public.wallet_security_log FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Keep audit log permissive for system logging
DROP POLICY IF EXISTS "System can insert audit logs" ON public.security_audit_log;
CREATE POLICY "Authenticated can insert audit logs"
ON public.security_audit_log FOR INSERT
TO authenticated
WITH CHECK (true);