-- Insert ETH and BNB liquidity pools if they don't exist
INSERT INTO public.liquidity_pools (pool_name, pool_symbol, pool_type, description, total_liquidity, apy_rate, is_active)
VALUES 
  ('Ethereum Liquidity Pool', 'ETH-LP', 'ethereum', 'Provide ETH liquidity to earn rewards from trading fees and yield farming', 0, 8.5, true),
  ('Binance Smart Chain Pool', 'BNB-LP', 'bnb', 'Provide BNB liquidity to earn rewards from BSC ecosystem activities', 0, 7.2, true)
ON CONFLICT (pool_symbol) DO UPDATE SET
  pool_name = EXCLUDED.pool_name,
  description = EXCLUDED.description,
  apy_rate = EXCLUDED.apy_rate,
  is_active = EXCLUDED.is_active;