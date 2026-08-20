-- Create function to backfill missing historical rewards
-- This ensures all pools get rewards from their creation date, not just from last_reward_date

CREATE OR REPLACE FUNCTION public.backfill_historical_rewards()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pool_record RECORD;
  days_eligible INTEGER;
  expected_total_reward NUMERIC;
  missing_reward NUMERIC;
  processed_pools INTEGER := 0;
  total_backfilled NUMERIC := 0;
  today DATE := CURRENT_DATE;
BEGIN
  -- Find all active pools that should have rewards but are missing them
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
      AND (lock_end_date IS NULL OR lock_end_date > NOW())
    ORDER BY created_at ASC
  LOOP
    -- Calculate total days eligible for rewards (from creation to today, excluding first 24h)
    days_eligible := GREATEST(0, (today - pool_record.created_at::DATE)::INTEGER);
    
    IF days_eligible = 0 THEN
      CONTINUE;
    END IF;
    
    -- Calculate what TOTAL rewards should be for this many days
    expected_total_reward := (pool_record.staked_amount * pool_record.effective_apy / 100.0 / 365.0) * days_eligible;
    
    -- Calculate missing rewards (what should be there minus what's actually there)
    missing_reward := expected_total_reward - COALESCE(pool_record.rewards_earned, 0);
    
    -- Only backfill if there's a significant missing amount (more than 0.01 to avoid rounding issues)
    IF missing_reward > 0.01 THEN
      -- Update the staking pool with backfilled rewards
      UPDATE user_staking_pools
      SET
        rewards_earned = expected_total_reward,
        balance = COALESCE(balance, 0) + missing_reward,
        last_reward_date = today,
        updated_at = NOW()
      WHERE id = pool_record.id;
      
      -- Create transaction record for backfilled historical rewards
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
        missing_reward,
        'historical_backfill',
        'wSTR',
        format('Historical backfill: %s wSTR rewards for %s pool (%sm duration) - %s days @ %s%% APY',
               missing_reward,
               pool_record.pool_type,
               COALESCE(pool_record.stake_duration_months, 3),
               days_eligible,
               pool_record.effective_apy),
        'completed',
        NOW()
      );
      
      processed_pools := processed_pools + 1;
      total_backfilled := total_backfilled + missing_reward;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'processed_pools', processed_pools,
    'total_backfilled_rewards', total_backfilled,
    'timestamp', NOW()
  );
END;
$$;