-- Add wSTR balance integration for fiat transfers

-- RLS policies for fiat_wallets
ALTER TABLE fiat_wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own fiat wallets" ON fiat_wallets;
CREATE POLICY "Users can view own fiat wallets" 
ON fiat_wallets FOR SELECT 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own fiat wallets" ON fiat_wallets;
CREATE POLICY "Users can insert own fiat wallets" 
ON fiat_wallets FOR INSERT 
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can manage all fiat wallets" ON fiat_wallets;
CREATE POLICY "Admins can manage all fiat wallets" 
ON fiat_wallets FOR ALL 
USING (is_admin(auth.uid()));

-- System can update fiat wallets for transfers
DROP POLICY IF EXISTS "System can update fiat wallets" ON fiat_wallets;
CREATE POLICY "System can update fiat wallets" 
ON fiat_wallets FOR UPDATE 
USING (true);

-- RLS policies for fiat_transactions
ALTER TABLE fiat_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own fiat transactions" ON fiat_transactions;
CREATE POLICY "Users can view own fiat transactions" 
ON fiat_transactions FOR SELECT 
USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

DROP POLICY IF EXISTS "Users can create own fiat transactions" ON fiat_transactions;
CREATE POLICY "Users can create own fiat transactions" 
ON fiat_transactions FOR INSERT 
WITH CHECK (auth.uid() = from_user_id);

DROP POLICY IF EXISTS "Admins can manage all fiat transactions" ON fiat_transactions;
CREATE POLICY "Admins can manage all fiat transactions" 
ON fiat_transactions FOR ALL 
USING (is_admin(auth.uid()));

-- System can update transactions
DROP POLICY IF EXISTS "System can update fiat transactions" ON fiat_transactions;
CREATE POLICY "System can update fiat transactions" 
ON fiat_transactions FOR UPDATE 
USING (true);

-- Create function to get user's wSTR balance
CREATE OR REPLACE FUNCTION get_user_wstr_balance(p_user_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Create function to convert wSTR to fiat
CREATE OR REPLACE FUNCTION convert_wstr_to_fiat(
  p_user_id uuid,
  p_wstr_amount numeric,
  p_target_currency text
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
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
  -- You can adjust this based on your tokenomics
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