
-- 1. Drop the public INSERT policy on arx_audit_trail (allows unauthenticated spoofing)
DROP POLICY IF EXISTS "Audit log insert" ON arx_audit_trail;

-- 2. Fix arss_transactions: replace the overly permissive balance correction policy
-- The current policy allows any authenticated user to insert balance_correction for ANY user_id
DROP POLICY IF EXISTS "System can create balance corrections" ON arss_transactions;

-- Replace with: users can only insert their own transactions, admins/seed_str_admins can insert for anyone
CREATE POLICY "Users can insert own transactions"
ON arss_transactions
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
);

CREATE POLICY "Admins can insert balance corrections"
ON arss_transactions
FOR INSERT
TO authenticated
WITH CHECK (
  (transaction_type = ANY (ARRAY['balance_correction'::text, 'system_fix'::text, 'staking_reward'::text]))
  AND public.has_role(auth.uid(), 'admin'::public.app_role)
);

CREATE POLICY "Seed STR admins can insert balance corrections"
ON arss_transactions
FOR INSERT
TO authenticated
WITH CHECK (
  (transaction_type = ANY (ARRAY['balance_correction'::text, 'system_fix'::text, 'staking_reward'::text]))
  AND public.has_role(auth.uid(), 'seed_str_admin'::public.app_role)
);

-- 3. Fix ccoin_network_transactions: restrict INSERT to card owners
DROP POLICY IF EXISTS "Authenticated can insert network transactions" ON ccoin_network_transactions;

CREATE POLICY "Users can insert own card transactions"
ON ccoin_network_transactions
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM ccoin_network_cards
    WHERE id = card_id AND user_id = auth.uid()
  )
);

-- 4. Fix guardian_safeguard_wallets: restrict SELECT to admins only
DROP POLICY IF EXISTS "Guardian users can view safeguard wallets" ON guardian_safeguard_wallets;

CREATE POLICY "Admins can view safeguard wallets"
ON guardian_safeguard_wallets
FOR SELECT
TO authenticated
USING (
  public.has_role(auth.uid(), 'admin'::public.app_role)
);

-- 5. Clear any plaintext GitHub tokens and NULL out the column
UPDATE github_integrations
SET access_token = NULL
WHERE access_token IS NOT NULL;
