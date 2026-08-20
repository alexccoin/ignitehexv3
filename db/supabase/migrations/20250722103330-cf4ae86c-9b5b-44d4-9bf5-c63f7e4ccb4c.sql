-- Reset all pool balances and values to zero
UPDATE public.founder_pools SET 
  balance = 0, 
  usd_value = 0, 
  last_price = 0,
  updated_at = now();

UPDATE public.founder_positions SET 
  current_usd_value = 0, 
  min_deposit_usd = 100000,
  updated_at = now();

-- Reset wallet pools to zero
UPDATE public.wallet_pools SET 
  balance = 0,
  updated_at = now();