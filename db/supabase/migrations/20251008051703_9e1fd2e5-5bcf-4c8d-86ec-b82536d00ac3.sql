-- Add STR$ stablecoin support - Part 1: Update constraints

-- 1. Drop the existing check constraint on pool_type
ALTER TABLE user_staking_pools 
DROP CONSTRAINT IF EXISTS user_staking_pools_pool_type_check;

-- 2. Add updated constraint including str_stable
ALTER TABLE user_staking_pools
ADD CONSTRAINT user_staking_pools_pool_type_check 
CHECK (pool_type IN ('str', 'ccos', 'domain', 'arss', 'wstr', 'estr', 'str_stable'));

-- 3. Initialize STR$ staking pools for all existing users
INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
SELECT 
  user_id,
  'str_stable' as pool_type,
  0 as balance,
  0 as staked_amount,
  0 as rewards_earned,
  0 as apy_rate,
  3 as stake_duration_months
FROM user_profiles
WHERE NOT EXISTS (
  SELECT 1 FROM user_staking_pools 
  WHERE user_staking_pools.user_id = user_profiles.user_id 
  AND user_staking_pools.pool_type = 'str_stable'
);

-- 4. Create function to automatically initialize STR$ pool for new users
CREATE OR REPLACE FUNCTION initialize_str_stable_pool()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (NEW.user_id, 'str_stable', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  RETURN NEW;
END;
$$;

-- 5. Create trigger for new users
DROP TRIGGER IF EXISTS auto_init_str_stable_pool ON user_profiles;
CREATE TRIGGER auto_init_str_stable_pool
  AFTER INSERT ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION initialize_str_stable_pool();
