-- Fix voucher crediting to properly set staking duration and APY

CREATE OR REPLACE FUNCTION credit_voucher_tokens(
  user_id_param uuid,
  token_type_param text,
  package_type_param text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  token_amount numeric;
  stake_duration integer := 3; -- Default 3-month staking period for vouchers
  calculated_apy numeric;
  result jsonb;
  pool_exists boolean;
BEGIN
  -- Map package types to token amounts using the centralized mapping
  CASE package_type_param
    -- New naming convention
    WHEN 'Foundation ($2,500) ≈ 274,401.67 STR' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5,000) ≈ 548,803.34 STR' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10,000) ≈ 1,097,606.69 STR' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25,000) ≈ 2,744,016.72 STR' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50,000) ≈ 5,488,033.44 STR' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100,000) ≈ 10,976,066.89 STR' THEN token_amount := 10976066.89;
    
    -- Old naming convention for STR
    WHEN 'STR-BASIC-2500' THEN token_amount := 274401.67;
    WHEN 'STR-PREMIUM-5000' THEN token_amount := 548803.34;
    WHEN 'STR-ELITE-10000' THEN token_amount := 1097606.69;
    WHEN 'STR-ENTERPRISE-25000' THEN token_amount := 2744016.72;
    
    -- Old naming convention for CCOS (correct CCOS amounts)
    WHEN 'CCOS-STARTER-2500' THEN token_amount := 277.78; -- 2500/9
    WHEN 'CCOS-PROFESSIONAL-5000' THEN token_amount := 555.56; -- 5000/9
    WHEN 'CCOS-BUSINESS-10000' THEN token_amount := 1111.11; -- 10000/9
    WHEN 'CCOS-CORPORATE-25000' THEN token_amount := 2777.78; -- 25000/9
    
    -- Old naming convention for ARSS
    WHEN 'ARSS-AI-2500' THEN token_amount := 274401.67;
    WHEN 'ARSS-PRO-5000' THEN token_amount := 548803.34;
    WHEN 'ARSS-ADVANCED-10000' THEN token_amount := 1097606.69;
    WHEN 'ARSS-SUPREME-25000' THEN token_amount := 2744016.72;
    
    ELSE 
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Invalid package type: ' || package_type_param
      );
  END CASE;

  -- Calculate APY based on token type and duration (3 months default)
  calculated_apy := CASE
    WHEN token_type_param = 'str' THEN 12.0  -- 11-13% for 3 months
    WHEN token_type_param = 'ccos' THEN 13.5  -- 12.5-14.5% for 3 months
    WHEN token_type_param = 'arss' THEN 12.0
    ELSE 12.0
  END;

  -- Initialize user staking pools if they don't exist
  PERFORM initialize_user_staking_pools(user_id_param);

  -- Check if pool exists
  SELECT EXISTS(
    SELECT 1 FROM user_staking_pools
    WHERE user_id = user_id_param AND pool_type = token_type_param
  ) INTO pool_exists;

  IF pool_exists THEN
    -- Update existing pool: add to both balance and staked_amount
    UPDATE user_staking_pools
    SET 
      balance = balance + token_amount,
      staked_amount = staked_amount + token_amount,
      stake_duration_months = COALESCE(stake_duration_months, stake_duration),
      apy_rate = COALESCE(apy_rate, calculated_apy),
      dynamic_apy = COALESCE(dynamic_apy, calculated_apy),
      lock_end_date = COALESCE(lock_end_date, NOW() + (stake_duration || ' months')::interval),
      updated_at = NOW()
    WHERE user_id = user_id_param AND pool_type = token_type_param;
  ELSE
    -- Create new pool with proper staking parameters
    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      balance,
      staked_amount,
      rewards_earned,
      apy_rate,
      dynamic_apy,
      stake_duration_months,
      lock_end_date,
      created_at,
      updated_at
    ) VALUES (
      user_id_param,
      token_type_param,
      token_amount,
      token_amount,
      0,
      calculated_apy,
      calculated_apy,
      stake_duration,
      NOW() + (stake_duration || ' months')::interval,
      NOW(),
      NOW()
    );
  END IF;

  -- Log the transaction
  INSERT INTO arss_transactions (
    user_id,
    amount,
    transaction_type,
    source_type,
    description,
    status,
    created_at
  ) VALUES (
    user_id_param,
    token_amount,
    'voucher_redemption',
    'voucher_system',
    format('Voucher redemption: %s (%s %s, %s months @ %s%% APY)',
           package_type_param, token_amount, token_type_param, stake_duration, calculated_apy),
    'completed',
    NOW()
  );

  -- Return success result
  RETURN jsonb_build_object(
    'success', true,
    'tokens_credited', token_amount,
    'token_type', token_type_param,
    'package_type', package_type_param,
    'stake_duration_months', stake_duration,
    'apy_rate', calculated_apy
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;