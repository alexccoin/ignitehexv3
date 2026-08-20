-- Fix 2: RLS Policy - Add WITH CHECK to user_profiles INSERT policy
DROP POLICY IF EXISTS "Users insert own profile secure" ON public.user_profiles;

CREATE POLICY "Users insert own profile secure"
ON public.user_profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Fix 4: Add search_path security to functions
-- List of functions that need search_path protection
CREATE OR REPLACE FUNCTION public.get_available_balance(
  p_user_id uuid,
  p_token_type text
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance numeric;
BEGIN
  SELECT COALESCE(SUM(balance), 0)
  INTO v_balance
  FROM user_staking_pools
  WHERE user_id = p_user_id
    AND pool_type = LOWER(p_token_type);
  
  RETURN v_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_staking_rewards(
  p_user_id uuid,
  p_pool_type text,
  p_stake_duration_months integer
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance numeric;
  v_apy numeric;
  v_rewards numeric;
BEGIN
  -- Get current balance
  SELECT balance INTO v_balance
  FROM user_staking_pools
  WHERE user_id = p_user_id
    AND pool_type = p_pool_type
    AND stake_duration_months = p_stake_duration_months;
  
  IF v_balance IS NULL THEN
    RETURN 0;
  END IF;
  
  -- Get APY based on duration
  v_apy := CASE p_stake_duration_months
    WHEN 3 THEN 0.05
    WHEN 6 THEN 0.10
    WHEN 12 THEN 0.20
    ELSE 0
  END;
  
  -- Calculate daily rewards
  v_rewards := (v_balance * v_apy) / 365;
  
  RETURN v_rewards;
END;
$$;

-- Fix 5: Add balance validation trigger for staking operations
CREATE OR REPLACE FUNCTION public.validate_staking_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Prevent negative balances
  IF NEW.balance < 0 THEN
    RAISE EXCEPTION 'Staking balance cannot be negative. Attempted balance: %', NEW.balance;
  END IF;
  
  -- Prevent unrealistic balances (overflow protection)
  IF NEW.balance > 999999999999999 THEN
    RAISE EXCEPTION 'Staking balance exceeds maximum allowed value';
  END IF;
  
  -- Prevent negative staked amounts
  IF NEW.staked_amount < 0 THEN
    RAISE EXCEPTION 'Staked amount cannot be negative';
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_staking_balance_trigger ON public.user_staking_pools;
CREATE TRIGGER validate_staking_balance_trigger
  BEFORE INSERT OR UPDATE ON public.user_staking_pools
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_staking_balance();

-- Add validation for wallet transactions
CREATE OR REPLACE FUNCTION public.validate_transaction_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Prevent negative amounts
  IF NEW.amount <= 0 THEN
    RAISE EXCEPTION 'Transaction amount must be positive. Attempted amount: %', NEW.amount;
  END IF;
  
  -- Prevent unrealistic amounts (overflow protection)
  IF NEW.amount > 999999999999999 THEN
    RAISE EXCEPTION 'Transaction amount exceeds maximum allowed value';
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_transaction_amount_trigger ON public.wallet_transactions;
CREATE TRIGGER validate_transaction_amount_trigger
  BEFORE INSERT ON public.wallet_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_transaction_amount();