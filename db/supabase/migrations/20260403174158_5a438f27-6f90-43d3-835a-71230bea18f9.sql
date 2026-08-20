
-- 1. Credit 50,000,000 STR vesting pool (1 year, 0% APY)
INSERT INTO public.user_staking_pools (
  user_id, pool_type, staked_amount, apy_rate, stake_duration_months, 
  lock_end_date, status, is_enhanced_pool, created_at
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23',
  'str',
  50000000,
  0,
  12,
  NOW() + INTERVAL '1 year',
  'active',
  false,
  NOW()
);

-- 2. Credit 1,000,000 STR delay reward pool (1 year, 0% APY)
INSERT INTO public.user_staking_pools (
  user_id, pool_type, staked_amount, apy_rate, stake_duration_months, 
  lock_end_date, status, is_enhanced_pool, created_at
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23',
  'str',
  1000000,
  0,
  12,
  NOW() + INTERVAL '1 year',
  'active',
  false,
  NOW()
);

-- 3. Log the 50M STR credit transaction
INSERT INTO public.arss_transactions (
  user_id, amount, transaction_type, source_type, currency, 
  description, status
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23',
  50000000,
  'admin_credit',
  'manual_str_credit',
  'STR',
  'Admin manual credit: 50,000,000 STR vesting (1 year, 0% APY) for Dietrich Duemler',
  'completed'
);

-- 4. Log the 1M STR delay reward transaction
INSERT INTO public.arss_transactions (
  user_id, amount, transaction_type, source_type, currency, 
  description, status
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23',
  1000000,
  'admin_credit',
  'manual_str_credit',
  'STR',
  'Admin manual credit: 1,000,000 STR delay reward (1 year vesting, 0% APY) for Dietrich Duemler',
  'completed'
);
