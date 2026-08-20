-- Add ARSS and wSTR token support to the platform

-- 1. Initialize ARSS staking pools for all existing users
INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
SELECT 
  user_id,
  'arss' as pool_type,
  0 as balance,
  0 as staked_amount,
  0 as rewards_earned,
  0 as apy_rate,
  3 as stake_duration_months
FROM user_profiles
WHERE NOT EXISTS (
  SELECT 1 FROM user_staking_pools 
  WHERE user_staking_pools.user_id = user_profiles.user_id 
  AND user_staking_pools.pool_type = 'arss'
);

-- 2. Initialize wSTR staking pools for all existing users
INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
SELECT 
  user_id,
  'wstr' as pool_type,
  0 as balance,
  0 as staked_amount,
  0 as rewards_earned,
  0 as apy_rate,
  3 as stake_duration_months
FROM user_profiles
WHERE NOT EXISTS (
  SELECT 1 FROM user_staking_pools 
  WHERE user_staking_pools.user_id = user_profiles.user_id 
  AND user_staking_pools.pool_type = 'wstr'
);

-- 3. Update the auto-initialization function to include ARSS and wSTR
CREATE OR REPLACE FUNCTION initialize_str_stable_pool()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Add STR$ pool
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (NEW.user_id, 'str_stable', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- Add ARSS pool
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (NEW.user_id, 'arss', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- Add wSTR pool
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (NEW.user_id, 'wstr', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  RETURN NEW;
END;
$$;