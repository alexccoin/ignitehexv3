-- Crypto wallets: remove user INSERT/UPDATE
DROP POLICY IF EXISTS "Users can update own crypto wallets" ON public.crypto_wallets;
DROP POLICY IF EXISTS "Users can insert own crypto wallets" ON public.crypto_wallets;

-- Staking rewards distribution: remove user INSERT
DROP POLICY IF EXISTS "Users can insert their own reward distributions" ON public.staking_rewards_distribution;

-- Fiat transactions: remove user INSERT policies
DROP POLICY IF EXISTS "Users can create fiat transactions" ON public.fiat_transactions;
DROP POLICY IF EXISTS "Users can create own fiat transactions" ON public.fiat_transactions;

-- Founder pool transactions: remove user DELETE
DROP POLICY IF EXISTS "Users can delete their own founder pool transactions" ON public.founder_pool_transactions;

-- Guardian flash alerts: restrict SELECT to admins only
DROP POLICY IF EXISTS "Authenticated users can view alerts" ON public.guardian_flash_alerts;
DROP POLICY IF EXISTS "All authenticated users can view alerts" ON public.guardian_flash_alerts;
DROP POLICY IF EXISTS "Users can view guardian flash alerts" ON public.guardian_flash_alerts;

CREATE POLICY "Admins can view guardian flash alerts"
ON public.guardian_flash_alerts
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'::app_role));
