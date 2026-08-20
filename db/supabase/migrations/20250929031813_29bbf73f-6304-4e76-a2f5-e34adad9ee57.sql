-- Drop existing function and recreate with proper vesting logic

-- Drop existing function first
DROP FUNCTION IF EXISTS public.get_user_enhanced_stakes(uuid);

-- Create proper vesting-aware reward distribution functions

-- First, create the calculate_dynamic_apy function if it doesn't exist
CREATE OR REPLACE FUNCTION public.calculate_dynamic_apy(
  str_amount numeric,
  duration_months integer,
  network_efficiency numeric DEFAULT 1.0
) RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_apy numeric;
  duration_multiplier numeric;
  network_multiplier numeric;
  final_apy numeric;
BEGIN
  -- Base APY rates by token type (assuming STR for now)
  base_apy := 11.0;
  
  -- Duration multipliers based on lock period
  CASE 
    WHEN duration_months >= 48 THEN duration_multiplier := 6.0;  -- 48+ months: up to 66% APY
    WHEN duration_months >= 36 THEN duration_multiplier := 4.5;  -- 36+ months: up to 49.5% APY
    WHEN duration_months >= 24 THEN duration_multiplier := 3.0;  -- 24+ months: up to 33% APY
    WHEN duration_months >= 12 THEN duration_multiplier := 2.0;  -- 12+ months: up to 22% APY
    WHEN duration_months >= 6 THEN duration_multiplier := 1.4;   -- 6+ months: up to 15.4% APY
    ELSE duration_multiplier := 1.0;  -- 3 months: base 11% APY
  END CASE;
  
  -- Network efficiency multiplier (1.0 = 100% efficiency)
  network_multiplier := GREATEST(0.5, LEAST(1.5, network_efficiency));
  
  -- Calculate final APY
  final_apy := base_apy * duration_multiplier * network_multiplier;
  
  -- Cap at reasonable maximum
  final_apy := LEAST(final_apy, 90.0);
  
  RETURN final_apy;
END;
$$;

-- Create the distribute_enhanced_rewards function for proper staking with vesting
CREATE OR REPLACE FUNCTION public.distribute_enhanced_rewards(
  user_id_param UUID,
  token_type_param TEXT,
  amount NUMERIC,
  duration_months_param INTEGER,
  network_efficiency_param NUMERIC DEFAULT 1.0
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  calculated_apy NUMERIC;
  lock_end_timestamp TIMESTAMP WITH TIME ZONE;
  existing_pool RECORD;
  result JSONB;
BEGIN
  -- Calculate dynamic APY based on amount and duration
  calculated_apy := calculate_dynamic_apy(amount, duration_months_param, network_efficiency_param);
  
  -- Calculate lock end date
  lock_end_timestamp := NOW() + INTERVAL '1 month' * duration_months_param;
  
  -- Check if user already has a pool for this token type
  SELECT * INTO existing_pool
  FROM user_staking_pools
  WHERE user_id = user_id_param 
    AND pool_type = token_type_param 
    AND is_enhanced_pool = true
  LIMIT 1;
  
  IF existing_pool.id IS NOT NULL THEN
    -- Update existing enhanced pool
    UPDATE user_staking_pools
    SET 
      staked_amount = staked_amount + amount,
      balance = balance + amount,
      stake_duration_months = duration_months_param,
      lock_end_date = lock_end_timestamp,
      dynamic_apy = calculated_apy,
      network_efficiency = network_efficiency_param,
      original_stake_amount = COALESCE(original_stake_amount, 0) + amount,
      updated_at = NOW()
    WHERE id = existing_pool.id;
  ELSE
    -- Create new enhanced staking pool
    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      balance,
      staked_amount,
      rewards_earned,
      apy_rate,
      stake_duration_months,
      lock_end_date,
      is_enhanced_pool,
      dynamic_apy,
      network_efficiency,
      original_stake_amount,
      created_at,
      updated_at
    ) VALUES (
      user_id_param,
      token_type_param,
      amount,
      amount,
      0,
      calculated_apy,
      duration_months_param,
      lock_end_timestamp,
      true,
      calculated_apy,
      network_efficiency_param,
      amount,
      NOW(),
      NOW()
    );
  END IF;
  
  -- Log the enhanced staking transaction
  INSERT INTO arss_transactions (
    user_id,
    transaction_type,
    amount,
    source_type,
    description,
    status,
    created_at
  ) VALUES (
    user_id_param,
    'stake',
    amount,
    'enhanced_staking',
    format('Enhanced staking: %s %s for %s months (APY: %s%%)', 
           amount, token_type_param, duration_months_param, calculated_apy),
    'completed',
    NOW()
  );
  
  result := jsonb_build_object(
    'success', true,
    'apy', calculated_apy,
    'lock_end_date', lock_end_timestamp,
    'duration_months', duration_months_param,
    'amount', amount,
    'message', 'Enhanced staking completed successfully'
  );
  
  RETURN result;
END;
$$;

-- Create function to get user's enhanced stakes
CREATE OR REPLACE FUNCTION public.get_user_enhanced_stakes(user_id_param UUID)
RETURNS TABLE(
  id UUID,
  pool_type TEXT,
  token_type TEXT,
  pool_name TEXT,
  balance NUMERIC,
  staked_amount NUMERIC,
  rewards_earned NUMERIC,
  dynamic_apy NUMERIC,
  duration_months INTEGER,
  lock_end_date TIMESTAMP WITH TIME ZONE,
  is_locked BOOLEAN,
  network_efficiency NUMERIC,
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    usp.id,
    usp.pool_type,
    usp.pool_type as token_type,
    CASE 
      WHEN usp.pool_type = 'str' THEN 'STR Enhanced Pool'
      WHEN usp.pool_type = 'ccos' THEN 'CCOS Enhanced Pool'
      WHEN usp.pool_type = 'domain' THEN 'Domain Enhanced Pool'
      ELSE 'Enhanced Pool'
    END as pool_name,
    usp.balance,
    usp.staked_amount,
    usp.rewards_earned,
    COALESCE(usp.dynamic_apy, usp.apy_rate) as dynamic_apy,
    COALESCE(usp.stake_duration_months, 3) as duration_months,
    usp.lock_end_date,
    CASE 
      WHEN usp.lock_end_date IS NULL THEN false
      WHEN usp.lock_end_date > NOW() THEN true
      ELSE false
    END as is_locked,
    COALESCE(usp.network_efficiency, 1.0) as network_efficiency,
    usp.created_at
  FROM user_staking_pools usp
  WHERE usp.user_id = user_id_param 
    AND usp.is_enhanced_pool = true
    AND usp.staked_amount > 0
  ORDER BY usp.created_at DESC;
END;
$$;