-- Complete Fix 4: Add search_path to remaining functions

CREATE OR REPLACE FUNCTION public.convert_wstr_to_fiat(
  p_user_id uuid, 
  p_wstr_amount numeric, 
  p_target_currency text
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wstr_balance numeric;
  v_conversion_rate numeric;
  v_fiat_amount numeric;
BEGIN
  -- Check wSTR balance
  v_wstr_balance := get_user_wstr_balance(p_user_id);
  
  IF v_wstr_balance < p_wstr_amount THEN
    RAISE EXCEPTION 'Insufficient wSTR balance. Available: %, Required: %', v_wstr_balance, p_wstr_amount;
  END IF;
  
  -- Get conversion rate (1 wSTR = 1 USD equivalent, then convert to target)
  CASE p_target_currency
    WHEN 'EUR' THEN v_conversion_rate := 0.92;
    WHEN 'GBP' THEN v_conversion_rate := 0.79;
    WHEN 'CHF' THEN v_conversion_rate := 0.88;
    WHEN 'USD' THEN v_conversion_rate := 1.0;
    ELSE v_conversion_rate := 1.0;
  END CASE;
  
  v_fiat_amount := p_wstr_amount * v_conversion_rate;
  
  -- Deduct wSTR from user
  INSERT INTO arss_transactions (
    user_id,
    transaction_type,
    amount,
    description,
    source_type,
    status
  ) VALUES (
    p_user_id,
    'debit',
    p_wstr_amount,
    'Converted to ' || p_target_currency || ' for fiat wallet',
    'wstr_conversion',
    'completed'
  );
  
  RETURN v_fiat_amount;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_wstr_balance(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance numeric;
BEGIN
  SELECT COALESCE(SUM(
    CASE 
      WHEN transaction_type IN ('credit', 'staking_reward', 'airdrop', 'purchase', 'manual_credit', 'voucher_credit') THEN amount
      WHEN transaction_type IN ('debit', 'withdrawal', 'transfer_out') THEN -amount
      ELSE 0
    END
  ), 0)
  INTO v_balance
  FROM arss_transactions
  WHERE user_id = p_user_id;
  
  RETURN v_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_ccoin_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;