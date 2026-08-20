-- Fix distribute_vested_rewards to ALWAYS distribute rewards as wSTR
-- and ensure consistency with manual-rewards-distribution

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
  -- Process all ACTIVE staking pools that need rewards
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
      AND apy_rate > 0
      AND status = 'active'
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
    
    -- CRITICAL: ALL staking rewards are ALWAYS in wSTR, regardless of staked token type
    INSERT INTO arss_transactions (
      user_id,
      transaction_type,
      amount,
      source_type,
      currency,
      description,
      status,
      created_at
    ) VALUES (
      pool_record.user_id,
      'staking_reward',
      total_reward,
      'daily_rewards',
      'wSTR',
      format('Daily wSTR staking reward for %s (%sm duration) - %s days @ %s%% APY',
             pool_record.pool_type,
             COALESCE(pool_record.stake_duration_months, 3),
             days_to_credit,
             pool_record.effective_apy),
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