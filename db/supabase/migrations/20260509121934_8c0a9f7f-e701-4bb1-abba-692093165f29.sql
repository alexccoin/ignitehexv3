
-- 1. Lock down arss_transactions: drop open user write policies
DROP POLICY IF EXISTS "Users can insert own transactions" ON public.arss_transactions;
DROP POLICY IF EXISTS "Users can create their own transactions" ON public.arss_transactions;

-- 2. Lock down ccoin_ledger: drop open user write policies
DROP POLICY IF EXISTS "Users can insert own ledger" ON public.ccoin_ledger;
DROP POLICY IF EXISTS "Users can insert own ledger records" ON public.ccoin_ledger;

-- 3. Lock down user_staking_pools: drop open user write/delete policies (admin policies remain; edge functions use service role)
DROP POLICY IF EXISTS "Users can insert their own staking pools" ON public.user_staking_pools;
DROP POLICY IF EXISTS "Users can update their own staking pools" ON public.user_staking_pools;
DROP POLICY IF EXISTS "Users can delete their own staking pools" ON public.user_staking_pools;

-- 4. Protect security-critical columns on user_profiles via trigger
CREATE OR REPLACE FUNCTION public.prevent_user_profile_security_field_writes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_admin_user boolean := false;
BEGIN
  -- Allow service role / superuser unconditionally (edge functions, triggers, migrations)
  IF current_setting('role', true) = 'service_role' OR session_user = 'postgres' THEN
    RETURN NEW;
  END IF;

  -- Allow admins
  BEGIN
    is_admin_user := public.is_admin(auth.uid());
  EXCEPTION WHEN OTHERS THEN
    is_admin_user := false;
  END;

  IF is_admin_user THEN
    RETURN NEW;
  END IF;

  -- For ordinary users, block changes to security-critical columns
  IF NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words THEN
    RAISE EXCEPTION 'wallet_recovery_words cannot be modified directly. Use the secure wallet recovery flow.';
  END IF;
  IF NEW.wallet_pin_hash IS DISTINCT FROM OLD.wallet_pin_hash THEN
    RAISE EXCEPTION 'wallet_pin_hash cannot be modified directly. Use the change-wallet-pin edge function.';
  END IF;
  IF NEW.two_factor_secret IS DISTINCT FROM OLD.two_factor_secret THEN
    RAISE EXCEPTION 'two_factor_secret cannot be modified directly. Use the 2FA setup flow.';
  END IF;
  IF NEW.backup_codes IS DISTINCT FROM OLD.backup_codes THEN
    RAISE EXCEPTION 'backup_codes cannot be modified directly. Use the secure backup flow.';
  END IF;
  -- encrypted variants if present
  BEGIN
    IF NEW.wallet_recovery_words_encrypted IS DISTINCT FROM OLD.wallet_recovery_words_encrypted THEN
      RAISE EXCEPTION 'wallet_recovery_words_encrypted cannot be modified directly.';
    END IF;
  EXCEPTION WHEN undefined_column THEN
    -- column doesn't exist; ignore
    NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_user_profile_security_field_writes ON public.user_profiles;
CREATE TRIGGER trg_prevent_user_profile_security_field_writes
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_user_profile_security_field_writes();

-- 5. Atomic balance-debit RPCs (prevent race-condition double-spend)

-- Atomic fiat wallet debit: returns true if debit succeeded, false if insufficient.
CREATE OR REPLACE FUNCTION public.debit_fiat_wallet(
  p_user_id uuid,
  p_currency text,
  p_amount numeric
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_id uuid;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  UPDATE public.fiat_wallets
     SET balance = balance - p_amount,
         available_balance = available_balance - p_amount,
         updated_at = now()
   WHERE user_id = p_user_id
     AND currency = upper(p_currency)
     AND available_balance >= p_amount
   RETURNING id INTO v_updated_id;

  RETURN v_updated_id IS NOT NULL;
END;
$$;

-- Atomic staking pool balance debit
CREATE OR REPLACE FUNCTION public.debit_staking_pool_balance(
  p_user_id uuid,
  p_pool_type text,
  p_amount numeric
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pool_id uuid;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Pick the highest-balance pool that has enough, lock it, and debit atomically
  WITH candidate AS (
    SELECT id
      FROM public.user_staking_pools
     WHERE user_id = p_user_id
       AND pool_type = p_pool_type
       AND balance >= p_amount
     ORDER BY balance DESC
     LIMIT 1
     FOR UPDATE
  )
  UPDATE public.user_staking_pools usp
     SET balance = usp.balance - p_amount,
         updated_at = now()
    FROM candidate c
   WHERE usp.id = c.id
   RETURNING usp.id INTO v_pool_id;

  RETURN v_pool_id IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.debit_fiat_wallet(uuid, text, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.debit_staking_pool_balance(uuid, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.debit_fiat_wallet(uuid, text, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.debit_staking_pool_balance(uuid, text, numeric) TO service_role;
