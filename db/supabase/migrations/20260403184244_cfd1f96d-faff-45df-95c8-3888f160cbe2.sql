
-- Credit 3,333,332 STR vesting pool (1 year, 0% APY) for Dietrich Duemler
INSERT INTO public.user_staking_pools (
  user_id, pool_type, staked_amount, apy_rate, stake_duration_months, 
  lock_end_date, status, is_enhanced_pool, created_at
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23',
  'str',
  3333332,
  0,
  12,
  NOW() + INTERVAL '1 year',
  'active',
  false,
  NOW()
);

-- Log the transaction
INSERT INTO public.arss_transactions (
  user_id, amount, transaction_type, source_type, currency, 
  description, status
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23',
  3333332,
  'admin_credit',
  'manual_str_credit',
  'STR',
  'Admin manual credit: 3,333,332 STR vesting (1 year, 0% APY) for Dietrich Duemler',
  'completed'
);
