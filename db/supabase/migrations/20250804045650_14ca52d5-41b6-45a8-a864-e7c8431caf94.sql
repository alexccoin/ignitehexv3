-- Distribute daily rewards to ALL domain stakers (including same-day)
DO $$
DECLARE
  pool_record record;
  daily_reward NUMERIC;
  days_since_creation INTEGER;
  total_reward NUMERIC;
  total_pools_processed INTEGER := 0;
  total_rewards_distributed NUMERIC := 0;
BEGIN
  -- Calculate daily rewards for ALL domain pools with positive balances
  FOR pool_record IN 
    SELECT id, user_id, pool_type, balance, staked_amount, apy_rate, created_at, rewards_earned
    FROM user_staking_pools 
    WHERE pool_type = 'domain'
    AND staked_amount > 0
  LOOP
    -- Calculate days since creation (minimum 1 day to get rewards, but include same day as 1 day)
    days_since_creation := GREATEST(1, EXTRACT(DAY FROM (now() - pool_record.created_at))::INTEGER);
    
    -- Calculate daily reward: staked_amount * (APY / 365)
    daily_reward := pool_record.staked_amount * (pool_record.apy_rate / 100.0 / 365.0);
    
    -- Calculate total reward for all days since creation
    total_reward := daily_reward * days_since_creation;
    
    -- Only update if the calculated reward is different from current rewards_earned
    IF pool_record.rewards_earned != total_reward THEN
      -- Update the staking pool with earned rewards
      UPDATE user_staking_pools 
      SET 
        rewards_earned = total_reward,
        balance = pool_record.staked_amount + total_reward,
        updated_at = now()
      WHERE id = pool_record.id;
      
      -- Log the reward transaction only if new rewards are being added
      IF total_reward > pool_record.rewards_earned THEN
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
          total_reward - pool_record.rewards_earned,
          'staking_reward',
          'Daily domain staking rewards - ' || days_since_creation || ' days (APY: ' || pool_record.apy_rate || '%)',
          'completed',
          now()
        );
      END IF;
      
      total_pools_processed := total_pools_processed + 1;
      total_rewards_distributed := total_rewards_distributed + (total_reward - pool_record.rewards_earned);
    END IF;
    
    RAISE NOTICE 'Domain Pool ID %: % days of rewards: % wSTR (daily: %, total: %)', pool_record.id, days_since_creation, total_reward, daily_reward, total_reward;
  END LOOP;
  
  RAISE NOTICE 'DOMAIN REWARDS SUMMARY: Processed % pools, distributed % additional wSTR in rewards', total_pools_processed, total_rewards_distributed;
END $$;