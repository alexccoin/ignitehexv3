-- Fix zero APY domain staking pools
-- Set correct APY rates based on stake_duration_months

UPDATE user_staking_pools
SET 
  apy_rate = CASE stake_duration_months
    WHEN 3 THEN 5
    WHEN 6 THEN 10
    WHEN 9 THEN 15
    WHEN 12 THEN 20
    WHEN 24 THEN 25
    WHEN 36 THEN 30
    WHEN 48 THEN 35
    ELSE 10  -- Default fallback
  END,
  updated_at = now()
WHERE pool_type = 'domain' 
  AND apy_rate = 0 
  AND staked_amount > 0;