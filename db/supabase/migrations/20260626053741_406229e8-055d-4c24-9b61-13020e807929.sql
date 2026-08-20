
-- 1) SAFE purchases: tighten WITH CHECK
DROP POLICY IF EXISTS "Anyone can submit SAFE subscription" ON public.safe_purchases;
CREATE POLICY "Anyone can submit SAFE subscription"
ON public.safe_purchases
FOR INSERT
TO anon, authenticated
WITH CHECK (
  status = 'pending'
  AND price_per_share_usd = 20
  AND shares BETWEEN 500 AND 25000
  AND total_usd = shares * 20
  AND credited_shares IS NULL
  AND credited_at IS NULL
  AND credited_by IS NULL
  AND bonus_pct = CASE
        WHEN shares >= 25000 THEN 12.5
        WHEN shares >= 10000 THEN 10
        WHEN shares >= 5000  THEN 5
        WHEN shares >= 2500  THEN 2.5
        ELSE 0
      END
  AND total_shares = shares + bonus_shares
);

-- 2) Founder positions: restrict INSERT to safe defaults
DROP POLICY IF EXISTS "Users can insert their own founder positions" ON public.founder_positions;
CREATE POLICY "Users can insert their own founder positions"
ON public.founder_positions
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND auth.uid() IS NOT NULL
  AND status = 'active'
  AND current_usd_value = 0
  AND COALESCE(input_btc_amount, 0)     = 0
  AND COALESCE(output_btc_amount, 0)    = 0
  AND COALESCE(expected_btc_return, 0)  = 0
  AND COALESCE(ccos_mint_percentage, 0) = 0
  AND COALESCE(withdrawal_executed, false) = false
  AND withdrawal_transaction_hash IS NULL
);

-- 3) user_profiles: restrict UPDATE to non-sensitive columns via column-level grants
REVOKE UPDATE ON public.user_profiles FROM authenticated;
GRANT UPDATE (
  full_name,
  address,
  city,
  country,
  postal_code,
  region,
  str_domain_username,
  str_domain_owned,
  bsc_wallet_address,
  btc_wallet_address,
  str_wallet_address,
  ccoin_visa_card,
  recovery_words_encrypted,
  recovery_words_iv,
  recovery_words_shown,
  device_fingerprints,
  ip_address,
  encryption_version,
  referral_code,
  referred_by,
  airdrop_applications_count,
  last_airdrop_application_date,
  wallet_setup_completed,
  wallet_created_at,
  updated_at
) ON public.user_profiles TO authenticated;

-- 4) Drop leftover "true" service_role-only policies (service_role bypasses RLS)
DROP POLICY IF EXISTS "Service role can manage balance correction jobs" ON public.balance_correction_jobs;
DROP POLICY IF EXISTS "Service role manages cache" ON public.staking_data_cache;
