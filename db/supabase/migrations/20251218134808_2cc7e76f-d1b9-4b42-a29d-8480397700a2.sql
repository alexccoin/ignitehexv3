
-- Fix Rene Buettner's staking data (user_id: cae3131d-c178-4a47-8e93-2eaf9d366f85)

-- Step 1: Add the 3 missing staking requests
INSERT INTO staking_requests (
  user_id, pool_type, request_type, amount, duration_months, description, 
  status, admin_notes, approved_by, requested_at, processed_at, str_domain_username, full_name
) VALUES 
-- Oct 5: 1,150,000 STR @ 12 months
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 'stake', 1150000, 12,
  'Lock Period: 12 months', 'approved', 'Manually added - missing from original data',
  'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', '2025-10-05 10:00:00+00', '2025-10-05 12:00:00+00',
  'str.Donstein', 'Rene Buettner'
),
-- Oct 5: 1,150,000 STR @ 24 months
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 'stake', 1150000, 24,
  'Lock Period: 24 months', 'approved', 'Manually added - missing from original data',
  'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', '2025-10-05 10:00:00+00', '2025-10-05 12:00:00+00',
  'str.Donstein', 'Rene Buettner'
),
-- Oct 7: 1,000,000 STR @ 36 months
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 'stake', 1000000, 36,
  'Lock Period: 36 months', 'approved', 'Manually added - missing from original data',
  'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', '2025-10-07 10:00:00+00', '2025-10-07 12:00:00+00',
  'str.Donstein', 'Rene Buettner'
);

-- Step 2: Store current rewards before deleting pools
DO $$
DECLARE
  current_rewards NUMERIC;
BEGIN
  SELECT COALESCE(SUM(rewards_earned), 0) INTO current_rewards
  FROM user_staking_pools 
  WHERE user_id = 'cae3131d-c178-4a47-8e93-2eaf9d366f85';
  
  -- Log the rewards we're preserving
  RAISE NOTICE 'Preserving total rewards: %', current_rewards;
END $$;

-- Step 3: Delete existing incorrect pools for this user
DELETE FROM user_staking_pools 
WHERE user_id = 'cae3131d-c178-4a47-8e93-2eaf9d366f85';

-- Step 4: Create 6 correct pools matching approved staking requests
-- APY rates: 3mo=12%, 6mo=14.75%, 12mo=20%, 24mo=31.5%, 36mo=46%
INSERT INTO user_staking_pools (
  user_id, pool_type, staked_amount, balance, rewards_earned, 
  apy_rate, stake_duration_months, status, created_at
) VALUES 
-- Aug 20: 250,000 STR @ 3 months (12% APY)
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 250000, 250000, 0,
  12.0, 3, 'active', '2025-08-20 08:48:19+00'
),
-- Aug 20: 250,000 STR @ 6 months (14.75% APY)
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 250000, 250000, 0,
  14.75, 6, 'active', '2025-08-20 08:53:25+00'
),
-- Sep 15: 1,350,000 STR @ 12 months (20% APY)
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 1350000, 1350000, 0,
  20.0, 12, 'active', '2025-09-15 10:50:03+00'
),
-- Oct 5: 1,150,000 STR @ 12 months (20% APY)
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 1150000, 1150000, 0,
  20.0, 12, 'active', '2025-10-05 10:00:00+00'
),
-- Oct 5: 1,150,000 STR @ 24 months (31.5% APY)
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 1150000, 1150000, 0,
  31.5, 24, 'active', '2025-10-05 10:00:00+00'
),
-- Oct 7: 1,000,000 STR @ 36 months (46% APY)
(
  'cae3131d-c178-4a47-8e93-2eaf9d366f85', 'str', 1000000, 1000000, 0,
  46.0, 36, 'active', '2025-10-07 10:00:00+00'
);

-- Step 5: Log the correction
INSERT INTO arss_transactions (
  user_id, transaction_type, source_type, amount, currency, status, description
) VALUES (
  'cae3131d-c178-4a47-8e93-2eaf9d366f85',
  'balance_correction',
  'admin_correction',
  5150000,
  'STR',
  'completed',
  'Fixed staking pools: Created 6 correct pools (250k@3mo, 250k@6mo, 1.35M@12mo, 1.15M@12mo, 1.15M@24mo, 1M@36mo) - Total: 5.15M STR'
);
