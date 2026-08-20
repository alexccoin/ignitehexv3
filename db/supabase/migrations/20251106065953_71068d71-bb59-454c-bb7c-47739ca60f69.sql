-- Fix daily rewards distribution to properly handle all staking periods and daily calculations

-- Create the distribute_vested_rewards function that's called by calculate-daily-rewards edge function
CREATE OR REPLACE FUNCTION public.distribute_vested_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pool_record RECORD;
  daily_reward NUMERIC;
  days_to_credit INTEGER;
  total_reward NUMERIC;
  processed_pools INTEGER := 0;
  total_rewards_distributed NUMERIC := 0;
  today DATE := CURRENT_DATE;
BEGIN
  -- Process all staking pools that need rewards
  FOR pool_record IN
    SELECT 
      id,
      user_id,
      pool_type,
      staked_amount,
      balance,
      rewards_earned,
      apy_rate,
      COALESCE(dynamic_apy, apy_rate) as effective_apy,
      stake_duration_months,
      created_at,
      last_reward_date,
      lock_end_date
    FROM user_staking_pools
    WHERE staked_amount > 0
      AND created_at < NOW() - INTERVAL '1 day'
      AND (last_reward_date IS NULL OR last_reward_date < today)
      AND (lock_end_date IS NULL OR lock_end_date > NOW())
    ORDER BY created_at ASC
  LOOP
    -- Calculate days since last reward (or since creation if never rewarded)
    IF pool_record.last_reward_date IS NOT NULL THEN
      days_to_credit := GREATEST(1, (today - pool_record.last_reward_date)::INTEGER);
    ELSE
      days_to_credit := GREATEST(1, (today - pool_record.created_at::DATE)::INTEGER);
    END IF;
    
    -- Calculate daily reward: (staked_amount * APY%) / 365 days
    daily_reward := (pool_record.staked_amount * pool_record.effective_apy / 100.0) / 365.0;
    
    -- Calculate total reward for the days to credit
    total_reward := daily_reward * days_to_credit;
    
    -- Update the staking pool
    UPDATE user_staking_pools
    SET
      rewards_earned = COALESCE(rewards_earned, 0) + total_reward,
      balance = COALESCE(balance, 0) + total_reward,
      last_reward_date = today,
      updated_at = NOW()
    WHERE id = pool_record.id;
    
    -- Create transaction record
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
      'reward',
      total_reward,
      'daily_staking_reward',
      format('Daily reward: %s pool, %s days @ %s%% APY, %s months',
             pool_record.pool_type, days_to_credit, pool_record.effective_apy,
             COALESCE(pool_record.stake_duration_months, 0)),
      'completed',
      NOW()
    );
    
    processed_pools := processed_pools + 1;
    total_rewards_distributed := total_rewards_distributed + total_reward;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'processed_pools', processed_pools,
    'total_rewards_distributed', total_rewards_distributed,
    'timestamp', NOW()
  );
END;
$$;

-- Helper function to update APY based on duration
CREATE OR REPLACE FUNCTION public.update_pool_apy_by_duration()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pool_record RECORD;
  new_apy NUMERIC;
  updated_count INTEGER := 0;
BEGIN
  FOR pool_record IN
    SELECT id, pool_type, stake_duration_months, apy_rate
    FROM user_staking_pools
    WHERE stake_duration_months IS NOT NULL AND staked_amount > 0
  LOOP
    new_apy := CASE
      WHEN pool_record.pool_type = 'str' THEN
        CASE
          WHEN pool_record.stake_duration_months >= 48 THEN 70.0
          WHEN pool_record.stake_duration_months >= 36 THEN 46.0
          WHEN pool_record.stake_duration_months >= 24 THEN 31.5
          WHEN pool_record.stake_duration_months >= 12 THEN 20.0
          WHEN pool_record.stake_duration_months >= 6 THEN 14.75
          ELSE 12.0
        END
      WHEN pool_record.pool_type = 'ccos' THEN
        CASE
          WHEN pool_record.stake_duration_months >= 48 THEN 76.25
          WHEN pool_record.stake_duration_months >= 36 THEN 52.0
          WHEN pool_record.stake_duration_months >= 24 THEN 35.75
          WHEN pool_record.stake_duration_months >= 12 THEN 22.5
          WHEN pool_record.stake_duration_months >= 6 THEN 16.5
          ELSE 13.5
        END
      WHEN pool_record.pool_type = 'domain' THEN
        CASE
          WHEN pool_record.stake_duration_months >= 48 THEN 82.5
          WHEN pool_record.stake_duration_months >= 36 THEN 57.5
          WHEN pool_record.stake_duration_months >= 24 THEN 40.0
          WHEN pool_record.stake_duration_months >= 12 THEN 25.0
          WHEN pool_record.stake_duration_months >= 9 THEN 21.5
          WHEN pool_record.stake_duration_months >= 6 THEN 18.0
          ELSE 18.0
        END
      ELSE 12.0
    END;
    
    IF pool_record.apy_rate != new_apy THEN
      UPDATE user_staking_pools
      SET apy_rate = new_apy, dynamic_apy = new_apy, updated_at = NOW()
      WHERE id = pool_record.id;
      updated_count := updated_count + 1;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object('success', true, 'updated_count', updated_count);
END;
$$;