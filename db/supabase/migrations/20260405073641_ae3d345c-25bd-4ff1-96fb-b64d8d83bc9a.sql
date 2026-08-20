
-- Credit 2,222,223 STR to Dietrich Duemler (1-year vesting, 0% APY)
INSERT INTO public.user_staking_pools (
  user_id, pool_type, staked_amount, balance, apy_rate, stake_duration_months,
  lock_end_date, status, created_at, updated_at
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23', 'str', 2222223, 2222223, 0, 12,
  NOW() + INTERVAL '1 year', 'active', NOW(), NOW()
);

-- Log the transaction
INSERT INTO public.arss_transactions (
  user_id, transaction_type, amount, description, source_type, currency, status
) VALUES (
  '1939ed38-6e2c-47ff-b833-df1f746f6d23', 'admin_credit', 2222223,
  'Admin manual STR credit of 2,222,223 STR - adjustment to reach total 156,555,554 STR',
  'manual_str_credit', 'STR', 'completed'
);
