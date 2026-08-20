
-- Fix 1: Tighten safe_purchases INSERT policy to prevent user_id spoofing
DROP POLICY IF EXISTS "Anyone can submit SAFE subscription" ON public.safe_purchases;
CREATE POLICY "Anyone can submit SAFE subscription"
ON public.safe_purchases
FOR INSERT
TO anon, authenticated
WITH CHECK (user_id IS NULL OR user_id = auth.uid());

-- Fix 2: Atomic wSTR -> fiat conversion (row-locking prevents double-spend race)
CREATE OR REPLACE FUNCTION public.convert_wstr_to_fiat_atomic(
  p_user_id uuid,
  p_wstr_amount numeric,
  p_fiat_amount numeric,
  p_currency text,
  p_description text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance numeric;
BEGIN
  -- Lock all of the user's arss_transactions rows so concurrent conversions serialize
  PERFORM 1 FROM public.arss_transactions
    WHERE user_id = p_user_id
    FOR UPDATE;

  SELECT COALESCE(SUM(
    CASE
      WHEN transaction_type IN ('credit','staking_reward','airdrop','purchase','manual_credit','voucher_credit') THEN amount
      WHEN transaction_type IN ('debit','withdrawal','transfer_out') THEN -amount
      ELSE 0
    END
  ), 0)
  INTO v_balance
  FROM public.arss_transactions
  WHERE user_id = p_user_id;

  IF v_balance < p_wstr_amount THEN
    RAISE EXCEPTION 'Insufficient wSTR balance. Available: %, Required: %', v_balance, p_wstr_amount;
  END IF;

  INSERT INTO public.arss_transactions (user_id, transaction_type, amount, description, source_type, status)
  VALUES (p_user_id, 'debit', p_wstr_amount, p_description, 'wstr_conversion', 'completed');

  IF EXISTS (SELECT 1 FROM public.fiat_wallets WHERE user_id = p_user_id AND currency = p_currency) THEN
    UPDATE public.fiat_wallets
      SET balance = balance + p_fiat_amount,
          available_balance = available_balance + p_fiat_amount,
          updated_at = now()
      WHERE user_id = p_user_id AND currency = p_currency;
  ELSE
    INSERT INTO public.fiat_wallets (user_id, currency, balance, available_balance)
    VALUES (p_user_id, p_currency, p_fiat_amount, p_fiat_amount);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.convert_wstr_to_fiat_atomic(uuid, numeric, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.convert_wstr_to_fiat_atomic(uuid, numeric, numeric, text, text) TO service_role;
