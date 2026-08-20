
-- Fix 36-month pools by migrating them to closest available duration (48 months)
-- And create a 36-month enhanced pool if needed

-- Create 36-month enhanced pool for STR if it doesn't exist
INSERT INTO enhanced_staking_pools (
  name,
  theme,
  token_type,
  duration_months,
  apr_min,
  apr_max,
  min_stake_amount,
  max_stake_amount,
  status,
  description,
  icon
) VALUES (
  'STR Nova Stake',
  'cosmic',
  'str',
  36,
  50.00,
  60.00,
  50000,
  10000000,
  'active',
  'Premium 3-year enhanced stake with 50-60% dynamic APY',
  'star'
)
ON CONFLICT DO NOTHING;

-- Now update the 36-month pools to link to the correct enhanced pool
UPDATE user_staking_pools usp
SET 
  enhanced_pool_id = (
    SELECT id FROM enhanced_staking_pools 
    WHERE duration_months = 36 
    AND token_type = usp.pool_type 
    AND status = 'active' 
    LIMIT 1
  ),
  is_enhanced_pool = true,
  apy_rate = (
    SELECT apr_max FROM enhanced_staking_pools 
    WHERE duration_months = 36 
    AND token_type = usp.pool_type 
    AND status = 'active' 
    LIMIT 1
  ),
  dynamic_apy = (
    SELECT apr_max FROM enhanced_staking_pools 
    WHERE duration_months = 36 
    AND token_type = usp.pool_type 
    AND status = 'active' 
    LIMIT 1
  ),
  updated_at = now()
WHERE stake_duration_months = 36
AND staked_amount > 0
AND (enhanced_pool_id IS NULL OR is_enhanced_pool = false);

-- Verify the 36-month pools are now fixed
SELECT 
  'Fixed 36-month pools' as status,
  COUNT(*) as total_fixed,
  pool_type,
  AVG(apy_rate) as avg_apy
FROM user_staking_pools
WHERE stake_duration_months = 36
AND staked_amount > 0
GROUP BY pool_type;
