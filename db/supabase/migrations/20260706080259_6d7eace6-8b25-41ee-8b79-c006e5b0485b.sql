
-- 1. Extend user_profiles security-field trigger to cover account/user status & suspension/closure fields
CREATE OR REPLACE FUNCTION public.prevent_user_profile_security_field_writes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_admin_user boolean := false;
BEGIN
  IF current_setting('role', true) = 'service_role' OR session_user = 'postgres' THEN
    RETURN NEW;
  END IF;

  BEGIN
    is_admin_user := public.is_admin(auth.uid());
  EXCEPTION WHEN OTHERS THEN
    is_admin_user := false;
  END;

  IF is_admin_user THEN
    RETURN NEW;
  END IF;

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
  BEGIN
    IF NEW.wallet_recovery_words_encrypted IS DISTINCT FROM OLD.wallet_recovery_words_encrypted THEN
      RAISE EXCEPTION 'wallet_recovery_words_encrypted cannot be modified directly.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;

  -- Additional account-lifecycle / privilege columns must not be user-writable
  BEGIN
    IF NEW.account_status IS DISTINCT FROM OLD.account_status THEN
      RAISE EXCEPTION 'account_status can only be changed by an administrator.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN
    IF NEW.user_status IS DISTINCT FROM OLD.user_status THEN
      RAISE EXCEPTION 'user_status can only be changed by an administrator.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN
    IF NEW.profile_update_status IS DISTINCT FROM OLD.profile_update_status THEN
      RAISE EXCEPTION 'profile_update_status can only be changed by the review workflow.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN
    IF NEW.suspended_at IS DISTINCT FROM OLD.suspended_at THEN
      RAISE EXCEPTION 'suspended_at can only be changed by an administrator.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN
    IF NEW.suspension_reason IS DISTINCT FROM OLD.suspension_reason THEN
      RAISE EXCEPTION 'suspension_reason can only be changed by an administrator.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN
    IF NEW.closed_at IS DISTINCT FROM OLD.closed_at THEN
      RAISE EXCEPTION 'closed_at can only be changed by an administrator.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN
    IF NEW.closure_reason IS DISTINCT FROM OLD.closure_reason THEN
      RAISE EXCEPTION 'closure_reason can only be changed by an administrator.';
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;

  RETURN NEW;
END;
$$;

-- 2. Generic helper: check whether current transaction is running as service_role / superuser / admin
CREATE OR REPLACE FUNCTION public._current_is_privileged()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('role', true) = 'service_role' OR session_user = 'postgres' THEN
    RETURN true;
  END IF;
  BEGIN
    RETURN public.is_admin(auth.uid());
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;
END;
$$;

-- 3. arss_token_purchases: block user tampering with status / credited fields / amounts
CREATE OR REPLACE FUNCTION public.prevent_arss_token_purchases_tamper()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public._current_is_privileged() THEN RETURN NEW; END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'status can only be changed by an administrator.';
  END IF;
  BEGIN IF NEW.credited_at IS DISTINCT FROM OLD.credited_at THEN
    RAISE EXCEPTION 'credited_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.credited_amount IS DISTINCT FROM OLD.credited_amount THEN
    RAISE EXCEPTION 'credited_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
    RAISE EXCEPTION 'approved_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN
    RAISE EXCEPTION 'approved_by can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.token_amount IS DISTINCT FROM OLD.token_amount THEN
    RAISE EXCEPTION 'token_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.amount_usd IS DISTINCT FROM OLD.amount_usd THEN
    RAISE EXCEPTION 'amount_usd can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id cannot be reassigned.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_prevent_arss_token_purchases_tamper ON public.arss_token_purchases;
CREATE TRIGGER trg_prevent_arss_token_purchases_tamper
  BEFORE UPDATE ON public.arss_token_purchases
  FOR EACH ROW EXECUTE FUNCTION public.prevent_arss_token_purchases_tamper();

-- 4. crypto_orders
CREATE OR REPLACE FUNCTION public.prevent_crypto_orders_tamper()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public._current_is_privileged() THEN RETURN NEW; END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'status can only be changed by an administrator.'; END IF;
  BEGIN IF NEW.token_amount IS DISTINCT FROM OLD.token_amount THEN
    RAISE EXCEPTION 'token_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.usd_amount IS DISTINCT FROM OLD.usd_amount THEN
    RAISE EXCEPTION 'usd_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN
    RAISE EXCEPTION 'payment_status can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.payment_confirmed_at IS DISTINCT FROM OLD.payment_confirmed_at THEN
    RAISE EXCEPTION 'payment_confirmed_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.credited_at IS DISTINCT FROM OLD.credited_at THEN
    RAISE EXCEPTION 'credited_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id cannot be reassigned.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_prevent_crypto_orders_tamper ON public.crypto_orders;
CREATE TRIGGER trg_prevent_crypto_orders_tamper
  BEFORE UPDATE ON public.crypto_orders
  FOR EACH ROW EXECUTE FUNCTION public.prevent_crypto_orders_tamper();

-- 5. currency_exchanges
CREATE OR REPLACE FUNCTION public.prevent_currency_exchanges_tamper()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public._current_is_privileged() THEN RETURN NEW; END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'status can only be changed by an administrator.'; END IF;
  BEGIN IF NEW.from_amount IS DISTINCT FROM OLD.from_amount THEN
    RAISE EXCEPTION 'from_amount cannot be modified.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.to_amount IS DISTINCT FROM OLD.to_amount THEN
    RAISE EXCEPTION 'to_amount cannot be modified.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.exchange_rate IS DISTINCT FROM OLD.exchange_rate THEN
    RAISE EXCEPTION 'exchange_rate cannot be modified.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.fee IS DISTINCT FROM OLD.fee THEN
    RAISE EXCEPTION 'fee cannot be modified.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.completed_at IS DISTINCT FROM OLD.completed_at THEN
    RAISE EXCEPTION 'completed_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id cannot be reassigned.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_prevent_currency_exchanges_tamper ON public.currency_exchanges;
CREATE TRIGGER trg_prevent_currency_exchanges_tamper
  BEFORE UPDATE ON public.currency_exchanges
  FOR EACH ROW EXECUTE FUNCTION public.prevent_currency_exchanges_tamper();

-- 6. private_digital_shares_purchases
CREATE OR REPLACE FUNCTION public.prevent_private_digital_shares_purchases_tamper()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public._current_is_privileged() THEN RETURN NEW; END IF;
  BEGIN IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
        AND NEW.payment_status NOT IN ('awaiting_payment','payment_submitted') THEN
    RAISE EXCEPTION 'Only administrators can approve or complete a purchase.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.credited_at IS DISTINCT FROM OLD.credited_at THEN
    RAISE EXCEPTION 'credited_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
    RAISE EXCEPTION 'approved_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN
    RAISE EXCEPTION 'approved_by can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.shares_amount IS DISTINCT FROM OLD.shares_amount THEN
    RAISE EXCEPTION 'shares_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.total_amount IS DISTINCT FROM OLD.total_amount THEN
    RAISE EXCEPTION 'total_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id cannot be reassigned.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_prevent_priv_dig_shares_tamper ON public.private_digital_shares_purchases;
CREATE TRIGGER trg_prevent_priv_dig_shares_tamper
  BEFORE UPDATE ON public.private_digital_shares_purchases
  FOR EACH ROW EXECUTE FUNCTION public.prevent_private_digital_shares_purchases_tamper();

-- 7. private_str_prelisting_purchases
CREATE OR REPLACE FUNCTION public.prevent_private_str_prelisting_purchases_tamper()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public._current_is_privileged() THEN RETURN NEW; END IF;
  BEGIN IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
        AND NEW.payment_status NOT IN ('awaiting_payment','payment_submitted') THEN
    RAISE EXCEPTION 'Only administrators can approve or complete a purchase.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.status IS DISTINCT FROM OLD.status
        AND NEW.status NOT IN ('pending','awaiting_payment','payment_submitted') THEN
    RAISE EXCEPTION 'Only administrators can approve or complete a purchase.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.credited_at IS DISTINCT FROM OLD.credited_at THEN
    RAISE EXCEPTION 'credited_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
    RAISE EXCEPTION 'approved_at can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN
    RAISE EXCEPTION 'approved_by can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.token_amount IS DISTINCT FROM OLD.token_amount THEN
    RAISE EXCEPTION 'token_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.total_amount IS DISTINCT FROM OLD.total_amount THEN
    RAISE EXCEPTION 'total_amount can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.amount_usd IS DISTINCT FROM OLD.amount_usd THEN
    RAISE EXCEPTION 'amount_usd can only be changed by an administrator.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  BEGIN IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id cannot be reassigned.'; END IF;
  EXCEPTION WHEN undefined_column THEN NULL; END;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_prevent_priv_str_prelisting_tamper ON public.private_str_prelisting_purchases;
CREATE TRIGGER trg_prevent_priv_str_prelisting_tamper
  BEFORE UPDATE ON public.private_str_prelisting_purchases
  FOR EACH ROW EXECUTE FUNCTION public.prevent_private_str_prelisting_purchases_tamper();

-- 8. Atomic refund RPC - guards against concurrent double-credit
CREATE OR REPLACE FUNCTION public.refund_held_transfer_atomic(
  p_tx_id text,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transfer public.pending_transfers_treasury%ROWTYPE;
  v_total numeric;
  v_updated uuid;
BEGIN
  IF p_user_id IS NULL OR p_tx_id IS NULL THEN
    RAISE EXCEPTION 'Missing required parameters';
  END IF;

  -- Lock the row and ensure only a still-held transfer for this user is refunded once
  SELECT * INTO v_transfer
    FROM public.pending_transfers_treasury
   WHERE tx_id = p_tx_id
     AND from_user_id = p_user_id
     AND status = 'held'
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Transfer not found or already processed');
  END IF;

  IF v_transfer.held_until IS NOT NULL AND now() < v_transfer.held_until THEN
    RETURN jsonb_build_object('success', false, 'error', 'Hold period not elapsed', 'held_until', v_transfer.held_until);
  END IF;

  v_total := COALESCE(v_transfer.amount, 0) + COALESCE(v_transfer.fee, 0);

  -- Atomic wallet credit
  UPDATE public.fiat_wallets
     SET balance = balance + v_total,
         available_balance = available_balance + v_total,
         updated_at = now()
   WHERE user_id = p_user_id
     AND currency = v_transfer.currency
   RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'Wallet not found for currency %', v_transfer.currency;
  END IF;

  -- Guarded status transition: only still-held rows can flip to refunded
  UPDATE public.pending_transfers_treasury
     SET status = 'refunded',
         processed_at = now(),
         admin_notes = COALESCE(admin_notes,'') || ' | User requested refund after hold period'
   WHERE id = v_transfer.id
     AND status = 'held';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Concurrent refund detected';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'refunded_amount', v_total,
    'currency', v_transfer.currency
  );
END;
$$;

REVOKE ALL ON FUNCTION public.refund_held_transfer_atomic(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refund_held_transfer_atomic(text, uuid) TO service_role;

-- 9. Atomic wallet-to-wallet transfer for staking pools (prevents concurrent double-spend)
CREATE OR REPLACE FUNCTION public.transfer_staking_pool_atomic(
  p_from_user_id uuid,
  p_to_user_id uuid,
  p_pool_type text,
  p_amount numeric
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_id uuid;
  v_to_id uuid;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;
  IF p_from_user_id = p_to_user_id THEN
    RAISE EXCEPTION 'Cannot transfer to self';
  END IF;

  -- Atomic debit: only succeeds if sender has enough
  WITH candidate AS (
    SELECT id FROM public.user_staking_pools
     WHERE user_id = p_from_user_id
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
   RETURNING usp.id INTO v_from_id;

  IF v_from_id IS NULL THEN
    RETURN false;
  END IF;

  -- Credit receiver (upsert-style)
  UPDATE public.user_staking_pools
     SET balance = balance + p_amount,
         updated_at = now()
   WHERE user_id = p_to_user_id
     AND pool_type = p_pool_type
   RETURNING id INTO v_to_id;

  IF v_to_id IS NULL THEN
    INSERT INTO public.user_staking_pools
      (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, created_at, updated_at)
    VALUES
      (p_to_user_id, p_pool_type, p_amount, 0, 0, 0, now(), now());
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_staking_pool_atomic(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_staking_pool_atomic(uuid, uuid, text, numeric) TO service_role;
