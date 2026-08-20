-- Insert ETH and BNB liquidity pools if they don't exist
INSERT INTO public.liquidity_pools (pool_name, pool_symbol, pool_type, description, total_liquidity, apy_rate, is_active)
SELECT 'Ethereum Liquidity Pool', 'ETH-LP', 'ethereum', 'Provide ETH liquidity to earn rewards from trading fees and yield farming', 0, 8.5, true
WHERE NOT EXISTS (SELECT 1 FROM public.liquidity_pools WHERE pool_symbol = 'ETH-LP');

INSERT INTO public.liquidity_pools (pool_name, pool_symbol, pool_type, description, total_liquidity, apy_rate, is_active)
SELECT 'Binance Smart Chain Pool', 'BNB-LP', 'bnb', 'Provide BNB liquidity to earn rewards from BSC ecosystem activities', 0, 7.2, true
WHERE NOT EXISTS (SELECT 1 FROM public.liquidity_pools WHERE pool_symbol = 'BNB-LP');