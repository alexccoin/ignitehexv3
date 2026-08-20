
-- 1. cross_border_payments: remove user UPDATE
DROP POLICY IF EXISTS "Users can update their own cross-border payments" ON public.cross_border_payments;

-- 2. crypto_orders: remove user UPDATE
DROP POLICY IF EXISTS "Users can update own orders" ON public.crypto_orders;

-- 3. currency_exchanges: remove user UPDATE
DROP POLICY IF EXISTS "Users can update their own currency exchanges" ON public.currency_exchanges;

-- 4. guardian_wallets: remove user UPDATE
DROP POLICY IF EXISTS "Users can update own wallet addresses" ON public.guardian_wallets;

-- 5. prepaid_cards: remove user UPDATE (admin ALL policy remains)
DROP POLICY IF EXISTS "Users can update their own prepaid cards" ON public.prepaid_cards;

-- 6. user_liquidity_positions: remove user UPDATE
DROP POLICY IF EXISTS "Users can update their own positions" ON public.user_liquidity_positions;

-- 7. founder_positions: remove user DELETE
DROP POLICY IF EXISTS "Users can delete their own founder positions" ON public.founder_positions;

-- 8. private_str_prelisting_purchases: restrict user updates to awaiting_payment
DROP POLICY IF EXISTS "Users update own pending prelisting purchases" ON public.private_str_prelisting_purchases;

CREATE POLICY "Admins update all prelisting purchases"
ON public.private_str_prelisting_purchases
FOR UPDATE
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'seed_str_admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'seed_str_admin'::app_role));

CREATE POLICY "Users update own awaiting prelisting purchases"
ON public.private_str_prelisting_purchases
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id AND payment_status = 'awaiting_payment')
WITH CHECK (auth.uid() = user_id AND payment_status = 'awaiting_payment');

-- Trigger to block financial-field tampering on prelisting purchases by non-admins
CREATE OR REPLACE FUNCTION public.block_prelisting_purchase_financial_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW; -- service_role / no JWT: allow
  END IF;
  IF has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'seed_str_admin'::app_role) THEN
    RETURN NEW;
  END IF;
  IF NEW.str_amount IS DISTINCT FROM OLD.str_amount
     OR NEW.usd_amount IS DISTINCT FROM OLD.usd_amount
     OR NEW.price_per_str IS DISTINCT FROM OLD.price_per_str
     OR NEW.payment_amount IS DISTINCT FROM OLD.payment_amount
     OR NEW.payment_status IS DISTINCT FROM OLD.payment_status
     OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'Users cannot modify financial or status fields on prelisting purchases';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_prelisting_financial_tampering ON public.private_str_prelisting_purchases;
CREATE TRIGGER trg_block_prelisting_financial_tampering
BEFORE UPDATE ON public.private_str_prelisting_purchases
FOR EACH ROW
EXECUTE FUNCTION public.block_prelisting_purchase_financial_tampering();

-- 9. user_profiles: block sensitive-field changes by non-admin self-updates
CREATE OR REPLACE FUNCTION public.block_user_profile_sensitive_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW; -- service_role / no JWT: allow
  END IF;
  IF has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;
  IF NEW.account_status IS DISTINCT FROM OLD.account_status
     OR NEW.wallet_pin_hash IS DISTINCT FROM OLD.wallet_pin_hash
     OR NEW.wallet_recovery_words IS DISTINCT FROM OLD.wallet_recovery_words
     OR NEW.two_factor_secret IS DISTINCT FROM OLD.two_factor_secret
     OR NEW.backup_codes IS DISTINCT FROM OLD.backup_codes
     OR NEW.str_domain_owned IS DISTINCT FROM OLD.str_domain_owned
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.suspended_at IS DISTINCT FROM OLD.suspended_at
     OR NEW.suspension_reason IS DISTINCT FROM OLD.suspension_reason
     OR NEW.closed_at IS DISTINCT FROM OLD.closed_at
     OR NEW.closure_reason IS DISTINCT FROM OLD.closure_reason THEN
    RAISE EXCEPTION 'Users cannot modify sensitive account or wallet security fields on their own profile';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_user_profile_sensitive_tampering ON public.user_profiles;
CREATE TRIGGER trg_block_user_profile_sensitive_tampering
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.block_user_profile_sensitive_tampering();
