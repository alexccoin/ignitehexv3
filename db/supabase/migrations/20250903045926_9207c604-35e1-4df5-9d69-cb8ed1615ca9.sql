-- Add token_type support to enhanced_staking_pools
ALTER TABLE enhanced_staking_pools ADD COLUMN IF NOT EXISTS token_type TEXT NOT NULL DEFAULT 'str';
ALTER TABLE enhanced_staking_pools ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE enhanced_staking_pools ADD COLUMN IF NOT EXISTS icon TEXT DEFAULT 'zap';

-- Update existing pools to have STR token type
UPDATE enhanced_staking_pools SET token_type = 'str' WHERE token_type IS NULL OR token_type = '';

-- Add enhanced_pool_type to user_staking_pools for tracking enhanced stakes
ALTER TABLE user_staking_pools ADD COLUMN IF NOT EXISTS is_enhanced_pool BOOLEAN DEFAULT false;
ALTER TABLE user_staking_pools ADD COLUMN IF NOT EXISTS dynamic_apy NUMERIC;
ALTER TABLE user_staking_pools ADD COLUMN IF NOT EXISTS original_stake_amount NUMERIC;

-- Create enhanced staking distribution function
CREATE OR REPLACE FUNCTION public.distribute_enhanced_rewards(
  user_id_param UUID,
  token_type_param TEXT,
  amount NUMERIC,
  duration_months INTEGER,
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
  WHERE token_type = token_type_param
    AND duration_months = distribute_enhanced_rewards.duration_months
    AND status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No active enhanced pool found for ' || token_type_param || ' with ' || duration_months || ' months duration'
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

  -- Calculate dynamic APY using existing function
  SELECT calculate_dynamic_apy(amount, duration_months, network_efficiency_param) INTO calculated_apy;
  
  -- Calculate estimated annual reward
  estimated_reward := (amount * calculated_apy) / 100.0;
  
  -- Calculate lock end date
  lock_end_date := now() + (duration_months || ' months')::interval;

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
    duration_months,
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
    stake_duration_months = duration_months,
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
    'Enhanced staking: ' || amount || ' ' || UPPER(token_type_param) || ' in ' || pool_record.name || ' (' || calculated_apy || '% APY, ' || duration_months || ' months)',
    'completed'
  );

  result := jsonb_build_object(
    'success', true,
    'pool_name', pool_record.name,
    'token_type', token_type_param,
    'staked_amount', amount,
    'calculated_apy', calculated_apy,
    'estimated_annual_reward', estimated_reward,
    'duration_months', duration_months,
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

-- Create function to get user's enhanced stakes
CREATE OR REPLACE FUNCTION public.get_user_enhanced_stakes(target_user_id UUID)
RETURNS TABLE(
  id UUID,
  pool_type TEXT,
  pool_name TEXT,
  staked_amount NUMERIC,
  balance NUMERIC,
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
SET search_path TO 'public'
AS $$
BEGIN
  -- Check if user can access this data (own data or admin)
  IF NOT (auth.uid() = target_user_id OR is_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Access denied: can only view own enhanced stakes';
  END IF;

  RETURN QUERY
  SELECT 
    usp.id,
    usp.pool_type,
    COALESCE(esp.name, 'Enhanced ' || UPPER(usp.pool_type) || ' Pool') as pool_name,
    usp.staked_amount,
    usp.balance,
    usp.rewards_earned,
    usp.dynamic_apy,
    usp.stake_duration_months,
    usp.lock_end_date,
    CASE 
      WHEN usp.lock_end_date > now() THEN true 
      ELSE false 
    END as is_locked,
    usp.network_efficiency,
    usp.created_at
  FROM user_staking_pools usp
  LEFT JOIN enhanced_staking_pools esp ON usp.enhanced_pool_id = esp.id
  WHERE usp.user_id = target_user_id 
    AND usp.is_enhanced_pool = true
    AND usp.staked_amount > 0
  ORDER BY usp.created_at DESC;
END;
$$;

-- Insert default enhanced pools for all token types
INSERT INTO enhanced_staking_pools (name, token_type, duration_months, apr_min, apr_max, theme, description, icon, min_stake_amount, max_stake_amount) VALUES
-- STR Pools
('STR Spark Pool', 'str', 3, 11, 13, 'Quick ignition for STR tokens', 'Fast-track your STR rewards with our 3-month commitment pool', 'zap', 1000, 10000000),
('STR Pulse Vault', 'str', 6, 13.5, 16, 'Steady rhythm for STR growth', 'Medium-term STR staking with balanced risk and reward', 'activity', 1000, 10000000),
('STR Momentum Lock', 'str', 12, 18, 22, 'Annual STR commitment', 'One-year STR staking for serious long-term holders', 'trending-up', 1000, 10000000),
('STR Gravity Stake', 'str', 24, 28, 35, 'Long-term STR stability', 'Two-year commitment for maximum STR yield potential', 'anchor', 1000, 10000000),
('STR Eclipse Reserve', 'str', 48, 65, 75, 'Full-cycle STR staking', 'Four-year ultra-premium STR staking experience', 'sun', 1000, 10000000),

-- CCOS Pools  
('CCOS Spark Pool', 'ccos', 3, 12.5, 14.5, 'Quick ignition for CCOS tokens', 'Fast-track your CCOS rewards with our 3-month commitment pool', 'zap', 1000, 10000000),
('CCOS Pulse Vault', 'ccos', 6, 15, 17.5, 'Steady rhythm for CCOS growth', 'Medium-term CCOS staking with balanced risk and reward', 'activity', 1000, 10000000),
('CCOS Momentum Lock', 'ccos', 12, 20, 24, 'Annual CCOS commitment', 'One-year CCOS staking for serious long-term holders', 'trending-up', 1000, 10000000),
('CCOS Gravity Stake', 'ccos', 24, 30, 37, 'Long-term CCOS stability', 'Two-year commitment for maximum CCOS yield potential', 'anchor', 1000, 10000000),
('CCOS Eclipse Reserve', 'ccos', 48, 67, 77, 'Full-cycle CCOS staking', 'Four-year ultra-premium CCOS staking experience', 'sun', 1000, 10000000),

-- Domain Pools
('Domain Spark Pool', 'domain', 3, 13, 15, 'Quick ignition for Domain tokens', 'Fast-track your Domain rewards with our 3-month commitment pool', 'zap', 100, 1000000),
('Domain Pulse Vault', 'domain', 6, 16, 18.5, 'Steady rhythm for Domain growth', 'Medium-term Domain staking with balanced risk and reward', 'activity', 100, 1000000),
('Domain Momentum Lock', 'domain', 12, 21, 25, 'Annual Domain commitment', 'One-year Domain staking for serious long-term holders', 'trending-up', 100, 1000000),
('Domain Gravity Stake', 'domain', 24, 32, 39, 'Long-term Domain stability', 'Two-year commitment for maximum Domain yield potential', 'anchor', 100, 1000000),
('Domain Eclipse Reserve', 'domain', 48, 70, 80, 'Full-cycle Domain staking', 'Four-year ultra-premium Domain staking experience', 'sun', 100, 1000000)

ON CONFLICT (name, token_type, duration_months) DO UPDATE SET
  apr_min = EXCLUDED.apr_min,
  apr_max = EXCLUDED.apr_max,
  theme = EXCLUDED.theme,
  description = EXCLUDED.description,
  icon = EXCLUDED.icon,
  min_stake_amount = EXCLUDED.min_stake_amount,
  max_stake_amount = EXCLUDED.max_stake_amount,
  updated_at = now();