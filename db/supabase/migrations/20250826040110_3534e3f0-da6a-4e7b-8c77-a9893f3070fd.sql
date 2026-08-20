
-- First, let's add a column to track if tokens have been credited
ALTER TABLE voucher_redemptions 
ADD COLUMN tokens_credited BOOLEAN DEFAULT false,
ADD COLUMN credited_amount NUMERIC DEFAULT 0,
ADD COLUMN credited_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Create a function to credit tokens based on package type
CREATE OR REPLACE FUNCTION credit_voucher_tokens(
  voucher_id UUID,
  user_id_param UUID,
  token_type_param TEXT,
  package_type_param TEXT
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  credit_amount NUMERIC := 0;
  wallet_exists BOOLEAN := false;
BEGIN
  -- Determine credit amount based on package type
  CASE 
    WHEN package_type_param LIKE '%-2500' THEN credit_amount := 2500;
    WHEN package_type_param LIKE '%-5000' THEN credit_amount := 5000;
    WHEN package_type_param LIKE '%-10000' THEN credit_amount := 10000;
    WHEN package_type_param LIKE '%-25000' THEN credit_amount := 25000;
    ELSE credit_amount := 0;
  END CASE;
  
  -- Check if user has existing staking pools
  SELECT EXISTS(
    SELECT 1 FROM user_staking_pools 
    WHERE user_id = user_id_param AND pool_type = token_type_param
  ) INTO wallet_exists;
  
  -- Initialize staking pools if they don't exist
  IF NOT wallet_exists THEN
    PERFORM initialize_user_staking_pools(user_id_param);
  END IF;
  
  -- Credit the tokens to the appropriate pool
  UPDATE user_staking_pools 
  SET 
    balance = balance + credit_amount,
    staked_amount = staked_amount + credit_amount,
    updated_at = now()
  WHERE user_id = user_id_param AND pool_type = token_type_param;
  
  -- Update voucher redemption record
  UPDATE voucher_redemptions 
  SET 
    tokens_credited = true,
    credited_amount = credit_amount,
    credited_at = now(),
    updated_at = now()
  WHERE id = voucher_id;
  
  -- Log the transaction
  INSERT INTO arss_transactions (
    user_id,
    amount,
    transaction_type,
    source_type,
    description,
    status
  ) VALUES (
    user_id_param,
    credit_amount,
    'credit',
    'voucher_redemption',
    'Voucher redemption: ' || package_type_param,
    'completed'
  );
  
  RETURN credit_amount;
END;
$$;

-- Create a trigger function to automatically credit tokens when voucher is approved
CREATE OR REPLACE FUNCTION auto_credit_voucher_tokens()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only process if status changed to approved and tokens haven't been credited yet
  IF NEW.status = 'approved' AND OLD.status != 'approved' AND NEW.tokens_credited = false THEN
    PERFORM credit_voucher_tokens(NEW.id, NEW.user_id, NEW.token_type, NEW.package_type);
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create the trigger
CREATE TRIGGER auto_credit_voucher_trigger
  AFTER UPDATE ON voucher_redemptions
  FOR EACH ROW
  EXECUTE FUNCTION auto_credit_voucher_tokens();
