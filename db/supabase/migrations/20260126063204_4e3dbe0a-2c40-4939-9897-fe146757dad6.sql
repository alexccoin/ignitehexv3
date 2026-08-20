-- Update all STR staking pools for Seed STR credited users to proper 1-year vesting
-- This retroactively applies the correct vesting configuration

-- Step 1: Update existing STR pools for users with credited Seed STR applications
UPDATE user_staking_pools usp
SET 
  stake_duration_months = 12,
  lock_end_date = ssa.created_at + INTERVAL '1 year',
  apy_rate = 20, -- 12-month STR APY rate is 20%
  staked_amount = COALESCE(usp.staked_amount, 0) + 
    CASE WHEN COALESCE(usp.staked_amount, 0) = 0 THEN usp.balance ELSE 0 END,
  original_stake_amount = COALESCE(usp.original_stake_amount, usp.balance),
  last_reward_date = COALESCE(usp.last_reward_date, ssa.created_at::date),
  admin_notes = COALESCE(usp.admin_notes, '') || 
    CASE WHEN usp.admin_notes IS NULL OR usp.admin_notes = '' THEN '' ELSE ' | ' END ||
    'Seed STR investment - 1 year vesting from ' || ssa.created_at::date,
  updated_at = now()
FROM (
  SELECT DISTINCT ON (user_id) user_id, created_at
  FROM seed_str_applications
  WHERE credited_amount > 0
  ORDER BY user_id, created_at ASC
) ssa
WHERE usp.user_id = ssa.user_id
  AND usp.pool_type = 'str'
  AND (usp.stake_duration_months IS NULL OR usp.stake_duration_months != 12 OR usp.lock_end_date IS NULL);

-- Log this correction for audit purposes
INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, currency, description, status)
SELECT DISTINCT 
  s.user_id,
  0,
  'balance_correction',
  'seed_str_vesting_migration',
  'STR',
  'Seed STR tokens moved to 1-year vesting pool - retroactive correction',
  'completed'
FROM seed_str_applications s
WHERE s.credited_amount > 0;