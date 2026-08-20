
-- 1. fiat_wallets: remove user INSERT (creation handled by edge functions / triggers / admins)
DROP POLICY IF EXISTS "Users can insert own fiat wallets" ON public.fiat_wallets;

-- 2. fiat_transactions: remove user UPDATE
DROP POLICY IF EXISTS "Users can update own fiat transactions" ON public.fiat_transactions;

-- 3. transactions: remove user UPDATE
DROP POLICY IF EXISTS "Users update own transactions secure" ON public.transactions;

-- 4. founder_pool_transactions: remove user INSERT
DROP POLICY IF EXISTS "Users can insert their own founder pool transactions" ON public.founder_pool_transactions;

-- 5. user_plain_ibans: replace ALL user policy with SELECT only
DROP POLICY IF EXISTS "Users manage own plain ibans" ON public.user_plain_ibans;
CREATE POLICY "Users can view own plain ibans"
  ON public.user_plain_ibans
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- 6. user_plain_ccoin_cards: replace ALL user policy with SELECT only
DROP POLICY IF EXISTS "Users manage own plain ccoin cards" ON public.user_plain_ccoin_cards;
CREATE POLICY "Users can view own plain ccoin cards"
  ON public.user_plain_ccoin_cards
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);
