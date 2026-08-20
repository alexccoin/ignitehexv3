-- Initialize staking pools for str.alex user and add 50,000 stable $STR
INSERT INTO public.user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, status)
VALUES 
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'str', 0, 0, 0, 'active'),
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'wstr', 0, 0, 0, 'active'),
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'ccos', 0, 0, 0, 'active'),
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'arss', 0, 0, 0, 'active'),
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'estr', 0, 0, 0, 'active'),
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'domain', 0, 0, 0, 'active'),
  ('12b744d5-3692-4f63-94df-dea27e02abb6', 'str_stable', 50000, 0, 0, 'active');