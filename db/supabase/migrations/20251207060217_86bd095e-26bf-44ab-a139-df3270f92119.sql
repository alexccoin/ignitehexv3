-- Fix initialize_str_stable_pool trigger function to not use ON CONFLICT
CREATE OR REPLACE FUNCTION public.initialize_str_stable_pool()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pool_types TEXT[] := ARRAY['str_stable', 'arss', 'wstr', 'estr'];
  v_pool_type TEXT;
  v_exists BOOLEAN;
BEGIN
  FOREACH v_pool_type IN ARRAY v_pool_types
  LOOP
    -- Check if pool already exists
    SELECT EXISTS(
      SELECT 1 FROM user_staking_pools 
      WHERE user_id = NEW.user_id 
        AND pool_type = v_pool_type 
        AND stake_duration_months = 3
    ) INTO v_exists;
    
    -- Only insert if doesn't exist
    IF NOT v_exists THEN
      INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate, stake_duration_months)
      VALUES (NEW.user_id, v_pool_type, 0, 0, 0, 0, 3);
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$;