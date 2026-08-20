
-- 1) iban_accounts: remove ALL grant, keep SELECT-only for owners
DROP POLICY IF EXISTS "Users can manage own iban accounts" ON public.iban_accounts;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='iban_accounts'
      AND policyname='Users can view own iban accounts'
  ) THEN
    CREATE POLICY "Users can view own iban accounts"
      ON public.iban_accounts
      FOR SELECT
      TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- 2) founder_pools: remove user INSERT/UPDATE policies, keep SELECT-only
DROP POLICY IF EXISTS "Users can insert their own founder pools" ON public.founder_pools;
DROP POLICY IF EXISTS "Users can update their own founder pools" ON public.founder_pools;

-- 3) transactions: remove user INSERT policy
DROP POLICY IF EXISTS "Users insert own transactions secure" ON public.transactions;
