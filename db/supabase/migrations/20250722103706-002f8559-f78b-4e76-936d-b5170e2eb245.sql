-- Remove duplicate founder pools (keep the most recent one)
DELETE FROM public.founder_pools 
WHERE id NOT IN (
  SELECT DISTINCT ON (user_id, pool_type) id
  FROM public.founder_pools
  ORDER BY user_id, pool_type, created_at DESC
);

-- Remove duplicate wallet pools (keep the most recent one)
DELETE FROM public.wallet_pools 
WHERE id NOT IN (
  SELECT DISTINCT ON (user_id, pool_type) id
  FROM public.wallet_pools
  ORDER BY user_id, pool_type, created_at DESC
);

-- Reset all founder pool values to zero for specified assets
UPDATE public.founder_pools SET 
  balance = 0,
  usd_value = 0,
  last_price = 0,
  updated_at = now()
WHERE pool_type IN ('BTC', 'ETH', 'CCOS', 'STR', 'ARSS');

-- Reset all wallet pool values to zero for specified assets
UPDATE public.wallet_pools SET 
  balance = 0,
  updated_at = now()
WHERE pool_type IN ('BTC', 'ETH', 'CCOS', 'STR', 'ARSS');

-- Reset all founder positions to zero
UPDATE public.founder_positions SET 
  current_usd_value = 0,
  updated_at = now();