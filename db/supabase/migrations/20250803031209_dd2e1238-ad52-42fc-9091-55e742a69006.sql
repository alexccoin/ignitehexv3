-- Create the daily rewards function without cron dependency
CREATE OR REPLACE FUNCTION public.calculate_daily_rewards()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  pool_record RECORD;
  daily_reward NUMERIC;
  current_timestamp TIMESTAMP WITH TIME ZONE;
BEGIN
  current_timestamp := now();
  
  -- Loop through all active staking pools for approved users
  FOR pool_record IN 
    SELECT 
      usp.id,
      usp.user_id,
      usp.pool_type,
      usp.balance,
      usp.apy_rate,
      usp.created_at,
      up.status as account_status
    FROM user_staking_pools usp
    INNER JOIN user_profiles up ON usp.user_id = up.user_id
    WHERE usp.balance > 0 
      AND up.status = 'approved'
      AND usp.created_at <= (current_timestamp - INTERVAL '24 hours')
  LOOP
    -- Calculate daily reward: balance * (APY / 365)
    daily_reward := pool_record.balance * (pool_record.apy_rate / 100.0 / 365.0);
    
    -- Update the staking pool with earned rewards
    UPDATE user_staking_pools 
    SET 
      rewards_earned = rewards_earned + daily_reward,
      balance = balance + daily_reward,
      updated_at = current_timestamp
    WHERE id = pool_record.id;
    
    -- Log the reward transaction
    INSERT INTO arss_transactions (
      user_id,
      transaction_type,
      amount,
      source_type,
      description,
      status,
      created_at
    ) VALUES (
      pool_record.user_id,
      'earn',
      daily_reward,
      'staking_reward',
      'Daily staking reward for ' || pool_record.pool_type || ' pool (APY: ' || pool_record.apy_rate || '%)',
      'completed',
      current_timestamp
    );
    
  END LOOP;
  
  RAISE NOTICE 'Daily rewards calculation completed at %', current_timestamp;
END;
$function$;

-- Create a manual trigger function for rewards
CREATE OR REPLACE FUNCTION public.manual_calculate_rewards()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM calculate_daily_rewards();
  RETURN 'Daily rewards calculated successfully at ' || now();
END;
$function$;

-- Now manually run the rewards calculation for your account
SELECT public.manual_calculate_rewards();