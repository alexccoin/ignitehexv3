-- Add eSTR token support to the system
-- eSTR: Energy Sovereignty Token for Renewables

-- Update initialize_user_staking_pools function to include eSTR
CREATE OR REPLACE FUNCTION public.initialize_user_staking_pools(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- STR pool (3 months default)
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'str', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- CCOS pool (3 months default)
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'ccos', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- Domain pool (3 months default)
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'domain', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- STR$ stable pool (3 months default)
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'str_stable', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- ARSS pool (3 months default)
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'arss', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- wSTR pool (3 months default)
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'wstr', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  -- eSTR pool (Energy Sovereignty Token for Renewables) - NEW
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (target_user_id, 'estr', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
END;
$function$;

-- Update the trigger function to include eSTR initialization
CREATE OR REPLACE FUNCTION public.initialize_str_stable_pool()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  
  -- Add eSTR pool (Energy Sovereignty Token for Renewables) - NEW
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
  VALUES (NEW.user_id, 'estr', 0, 0, 0, 0, 3)
  ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  
  RETURN NEW;
END;
$function$;

-- Initialize eSTR pools for existing users
DO $$
DECLARE
  user_record RECORD;
BEGIN
  FOR user_record IN SELECT DISTINCT user_id FROM user_profiles LOOP
    INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
    VALUES (user_record.user_id, 'estr', 0, 0, 0, 0, 3)
    ON CONFLICT (user_id, pool_type, stake_duration_months) DO NOTHING;
  END LOOP;
END $$;