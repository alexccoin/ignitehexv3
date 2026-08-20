-- Distribute daily rewards to ALL eligible stakers
DO $$
DECLARE
  pool_record record;
  daily_reward NUMERIC;
  days_since_creation INTEGER;
  total_reward NUMERIC;
  total_pools_processed INTEGER := 0;
  total_rewards_distributed NUMERIC := 0;
BEGIN
  -- Calculate daily rewards for ALL users' staking pools with positive balances and at least 1 day old
  FOR pool_record IN 
    SELECT id, user_id, pool_type, balance, staked_amount, apy_rate, created_at
    FROM user_staking_pools 
    WHERE staked_amount > 0
    AND created_at < now() - INTERVAL '1 day'
    AND rewards_earned = 0  -- Only process pools that haven't received rewards yet
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
    
    total_pools_processed := total_pools_processed + 1;
    total_rewards_distributed := total_rewards_distributed + total_reward;
    
    RAISE NOTICE 'Pool ID %: % days of rewards for % pool: % wSTR (daily: %)', pool_record.id, days_since_creation, pool_record.pool_type, total_reward, daily_reward;
  END LOOP;
  
  RAISE NOTICE 'SUMMARY: Processed % pools, distributed % total wSTR in rewards', total_pools_processed, total_rewards_distributed;
END $$;