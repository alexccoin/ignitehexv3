-- Calculate and distribute daily rewards for the specific user
DO $$
DECLARE
  target_user_id UUID := 'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b';
  pool_record record;
  daily_reward NUMERIC;
  current_time TIMESTAMP WITH TIME ZONE := now();
BEGIN
  -- Calculate daily rewards for user's staking pools with positive balances
  FOR pool_record IN 
    SELECT id, user_id, pool_type, balance, staked_amount, apy_rate, created_at
    FROM user_staking_pools 
    WHERE user_id = target_user_id 
    AND staked_amount > 0
    AND created_at < (current_time - INTERVAL '1 day')  -- Only pools created more than 1 day ago
  LOOP
    -- Calculate daily reward: staked_amount * (APY / 365)
    daily_reward := pool_record.staked_amount * (pool_record.apy_rate / 100.0 / 365.0);
    
    -- Update the staking pool with earned rewards
    UPDATE user_staking_pools 
    SET 
      rewards_earned = COALESCE(rewards_earned, 0) + daily_reward,
      balance = COALESCE(balance, 0) + daily_reward,
      updated_at = current_time
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
      current_time
    );
    
    RAISE NOTICE 'Calculated reward for pool % (%) : % wSTR', pool_record.pool_type, pool_record.id, daily_reward;
  END LOOP;
END $$;