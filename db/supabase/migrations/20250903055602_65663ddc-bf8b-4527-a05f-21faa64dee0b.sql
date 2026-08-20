-- Drop both existing functions and recreate them with corrected parameters

-- Drop existing functions first  
DROP FUNCTION IF EXISTS public.calculate_dynamic_apy(numeric, integer, numeric);
DROP FUNCTION IF EXISTS public.distribute_enhanced_rewards(uuid, text, numeric, integer, numeric);

-- Create the calculate_dynamic_apy function with correct parameter names
CREATE OR REPLACE FUNCTION public.calculate_dynamic_apy(
  str_amount NUMERIC,
  duration_months INTEGER,
  network_efficiency NUMERIC DEFAULT 1.0
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  base_apy NUMERIC;
  amount_multiplier NUMERIC;
  duration_multiplier NUMERIC;
  efficiency_multiplier NUMERIC;
  final_apy NUMERIC;
  pool_record enhanced_staking_pools;
BEGIN
  -- Get the pool record to determine APY ranges
  SELECT * INTO pool_record
  FROM enhanced_staking_pools
  WHERE enhanced_staking_pools.duration_months = calculate_dynamic_apy.duration_months
    AND status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 10.0; -- Default fallback APY
  END IF;

  -- Base APY from pool configuration
  base_apy := pool_record.apr_min;

  -- Amount-based multiplier (higher stakes get better rates)
  -- Scale between min and max APY based on stake amount relative to pool limits
  amount_multiplier := LEAST(
    (str_amount - pool_record.min_stake_amount) / 
    GREATEST(pool_record.max_stake_amount - pool_record.min_stake_amount, 1.0),
    1.0
  );

  -- Duration-based multiplier (longer durations get incrementally better rates)
  duration_multiplier := 1.0 + (duration_months * 0.02); -- 2% bonus per month

  -- Network efficiency multiplier
  efficiency_multiplier := GREATEST(network_efficiency, 0.5); -- Minimum 50% efficiency

  -- Calculate final APY
  final_apy := base_apy + 
               (pool_record.apr_max - base_apy) * amount_multiplier * 
               duration_multiplier * 
               efficiency_multiplier;

  -- Ensure APY stays within pool bounds
  final_apy := GREATEST(pool_record.apr_min, LEAST(final_apy, pool_record.apr_max));

  RETURN ROUND(final_apy, 2);

EXCEPTION WHEN OTHERS THEN
  -- Return minimum APY on error
  RETURN COALESCE(pool_record.apr_min, 10.0);
END;
$$;

-- Create the distribute_enhanced_rewards function with corrected parameters
CREATE OR REPLACE FUNCTION public.distribute_enhanced_rewards(
  user_id_param UUID,
  token_type_param TEXT,
  amount NUMERIC,
  duration_months_param INTEGER,
  network_efficiency_param NUMERIC DEFAULT 1.0
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  pool_record enhanced_staking_pools;
  calculated_apy NUMERIC;
  estimated_reward NUMERIC;
  lock_end_date TIMESTAMP WITH TIME ZONE;
  result JSONB;
BEGIN
  -- Validate user authentication
  IF user_id_param IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User authentication required'
    );
  END IF;

  -- Get the enhanced staking pool for this token type and duration
  SELECT * INTO pool_record
  FROM enhanced_staking_pools
  WHERE enhanced_staking_pools.token_type = token_type_param
    AND enhanced_staking_pools.duration_months = duration_months_param
    AND enhanced_staking_pools.status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No active enhanced pool found for ' || token_type_param || ' with ' || duration_months_param || ' months duration'
    );
  END IF;

  -- Validate stake amount
  IF amount < pool_record.min_stake_amount THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Minimum stake amount is ' || pool_record.min_stake_amount || ' ' || UPPER(token_type_param)
    );
  END IF;

  IF amount > pool_record.max_stake_amount THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Maximum stake amount is ' || pool_record.max_stake_amount || ' ' || UPPER(token_type_param)
    );
  END IF;

  -- Calculate dynamic APY using the corrected function call
  SELECT calculate_dynamic_apy(amount, duration_months_param, network_efficiency_param) INTO calculated_apy;
  
  -- Calculate estimated annual reward
  estimated_reward := (amount * calculated_apy) / 100.0;
  
  -- Calculate lock end date
  lock_end_date := now() + (duration_months_param || ' months')::interval;

  -- Check if user already has a staking pool for this token type
  -- If not, create it first
  INSERT INTO user_staking_pools (
    user_id, 
    pool_type, 
    balance, 
    staked_amount, 
    rewards_earned, 
    apy_rate,
    is_enhanced_pool,
    dynamic_apy,
    original_stake_amount,
    enhanced_pool_id,
    stake_duration_months,
    lock_end_date,
    network_efficiency
  ) VALUES (
    user_id_param,
    token_type_param,
    amount, -- Initial balance equals staked amount
    amount,
    0, -- No rewards earned yet
    calculated_apy,
    true,
    calculated_apy,
    amount,
    pool_record.id,
    duration_months_param,
    lock_end_date,
    network_efficiency_param
  )
  ON CONFLICT (user_id, pool_type) 
  DO UPDATE SET
    balance = user_staking_pools.balance + amount,
    staked_amount = user_staking_pools.staked_amount + amount,
    apy_rate = calculated_apy,
    is_enhanced_pool = true,
    dynamic_apy = calculated_apy,
    original_stake_amount = COALESCE(user_staking_pools.original_stake_amount, 0) + amount,
    enhanced_pool_id = pool_record.id,
    stake_duration_months = duration_months_param,
    lock_end_date = lock_end_date,
    network_efficiency = network_efficiency_param,
    updated_at = now();

  -- Log the enhanced staking transaction
  INSERT INTO arss_transactions (
    user_id,
    transaction_type,
    amount,
    source_type,
    description,
    status
  ) VALUES (
    user_id_param,
    'stake',
    amount,
    'enhanced_staking',
    'Enhanced staking: ' || amount || ' ' || UPPER(token_type_param) || ' in ' || pool_record.name || ' (' || calculated_apy || '% APY, ' || duration_months_param || ' months)',
    'completed'
  );

  result := jsonb_build_object(
    'success', true,
    'pool_name', pool_record.name,
    'token_type', token_type_param,
    'staked_amount', amount,
    'calculated_apy', calculated_apy,
    'estimated_annual_reward', estimated_reward,
    'duration_months', duration_months_param,
    'lock_end_date', lock_end_date,
    'network_efficiency', network_efficiency_param
  );

  RETURN result;

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Enhanced staking failed: ' || SQLERRM
  );
END;
$$;