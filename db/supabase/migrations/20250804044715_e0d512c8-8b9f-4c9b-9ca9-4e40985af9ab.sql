-- Calculate and distribute daily rewards for the specific user (fixed version)
DO $$
DECLARE
  target_user_id UUID := 'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b';
  pool_record record;
  daily_reward NUMERIC;
  days_since_creation INTEGER;
  total_reward NUMERIC;
BEGIN
  -- Calculate daily rewards for user's staking pools with positive balances
  FOR pool_record IN 
    SELECT id, user_id, pool_type, balance, staked_amount, apy_rate, created_at
    FROM user_staking_pools 
    WHERE user_id = target_user_id 
    AND staked_amount > 0
  LOOP
    -- Calculate days since creation (minimum 1 day to get rewards)
    days_since_creation := GREATEST(1, EXTRACT(DAY FROM (now() - pool_record.created_at))::INTEGER);
    
    -- Calculate daily reward: staked_amount * (APY / 365)
    daily_reward := pool_record.staked_amount * (pool_record.apy_rate / 100.0 / 365.0);
    
    -- Calculate total reward for all days since creation
    total_reward := daily_reward * days_since_creation;
    
    -- Update the staking pool with earned rewards
    UPDATE user_staking_pools 
    SET 
      rewards_earned = total_reward,
      balance = pool_record.staked_amount + total_reward,
      updated_at = now()
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
      total_reward,
      'staking_reward',
      'Daily staking rewards for ' || pool_record.pool_type || ' pool - ' || days_since_creation || ' days (APY: ' || pool_record.apy_rate || '%)',
      'completed',
      now()
    );
    
    RAISE NOTICE 'Calculated % days of rewards for % pool: % wSTR (daily: %)', days_since_creation, pool_record.pool_type, total_reward, daily_reward;
  END LOOP;
END $$;