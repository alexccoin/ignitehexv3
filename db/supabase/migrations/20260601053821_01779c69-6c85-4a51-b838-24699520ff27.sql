-- Remove user UPDATE on founder_positions (financial state)
DROP POLICY IF EXISTS "Users can update their own founder positions" ON public.founder_positions;

-- Remove user UPDATE on iban_accounts (balance column)
DROP POLICY IF EXISTS "Users can update own IBAN accounts secure" ON public.iban_accounts;

-- Remove user UPDATE on user_wallets (arss_balance, total_earned, total_spent)
DROP POLICY IF EXISTS "Users can update their own wallet" ON public.user_wallets;