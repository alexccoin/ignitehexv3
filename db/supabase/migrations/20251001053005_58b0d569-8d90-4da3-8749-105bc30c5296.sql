-- 1) Ensure all required enhanced pools exist (STR, DOMAIN, CCOS)
WITH defs AS (
  SELECT * FROM (VALUES
    -- STR
    ('str'::text, 3, 13.0, 13.0, 'STR 3m Enhanced', 1000, 10000000, 'zap', 'brand'),
    ('str', 6, 16.0, 16.0, 'STR 6m Enhanced', 1000, 10000000, 'zap', 'brand'),
    ('str', 12, 22.0, 22.0, 'STR 12m Enhanced', 1000, 10000000, 'zap', 'brand'),
    ('str', 24, 35.0, 35.0, 'STR 24m Enhanced', 1000, 10000000, 'zap', 'brand'),
    ('str', 36, 60.0, 60.0, 'STR 36m Enhanced', 1000, 10000000, 'star', 'cosmic'),
    ('str', 48, 75.0, 75.0, 'STR 48m Enhanced', 1000, 10000000, 'zap', 'brand'),
    -- DOMAIN
    ('domain', 6, 18.5, 18.5, 'DOMAIN 6m Enhanced', 0, 10000000, 'shield', 'ocean'),
    ('domain', 9, 13.0, 13.0, 'DOMAIN 9m Enhanced', 0, 10000000, 'shield', 'ocean'),
    ('domain', 12, 25.0, 25.0, 'DOMAIN 12m Enhanced', 0, 10000000, 'shield', 'ocean'),
    ('domain', 24, 39.0, 39.0, 'DOMAIN 24m Enhanced', 0, 10000000, 'shield', 'ocean'),
    ('domain', 36, 22.0, 22.0, 'DOMAIN 36m Enhanced', 0, 10000000, 'shield', 'ocean'),
    ('domain', 48, 80.0, 80.0, 'DOMAIN 48m Enhanced', 0, 10000000, 'shield', 'ocean'),
    -- CCOS
    ('ccos', 3, 14.5, 14.5, 'CCOS 3m Enhanced', 0, 10000000, 'rocket', 'tech')
  ) AS v(token_type, duration_months, apr_min, apr_max, name, min_stake_amount, max_stake_amount, icon, theme)
)
INSERT INTO enhanced_staking_pools (
  name, theme, token_type, duration_months, apr_min, apr_max, min_stake_amount, max_stake_amount, status, reward_curve, compounding, description, icon
)
SELECT 
  d.name,
  d.theme,
  d.token_type,
  d.duration_months,
  d.apr_min,
  d.apr_max,
  d.min_stake_amount,
  d.max_stake_amount,
  'active'::pool_status,
  'linear'::reward_curve,
  false,
  d.name || ' auto-created to ensure correct APY mapping',
  d.icon
FROM defs d
WHERE NOT EXISTS (
  SELECT 1 FROM enhanced_staking_pools e
  WHERE e.token_type = d.token_type
    AND e.duration_months = d.duration_months
);

-- 2) Map ALL user pools to the correct enhanced pool and update APY fields
UPDATE user_staking_pools usp
SET 
  enhanced_pool_id = esp.id,
  is_enhanced_pool = true,
  apy_rate = esp.apr_max,
  dynamic_apy = esp.apr_max,
  stake_duration_months = esp.duration_months,
  lock_end_date = now() + (esp.duration_months || ' months')::interval,
  updated_at = now()
FROM enhanced_staking_pools esp
WHERE usp.pool_type = esp.token_type
  AND esp.status = 'active'
  AND usp.stake_duration_months = esp.duration_months
  AND (
    usp.enhanced_pool_id IS DISTINCT FROM esp.id
    OR usp.apy_rate IS DISTINCT FROM esp.apr_max
    OR usp.dynamic_apy IS DISTINCT FROM esp.apr_max
    OR usp.is_enhanced_pool IS DISTINCT FROM true
  );

-- 3) Handle pools without exact duration match - use closest
WITH closest_pools AS (
  SELECT DISTINCT ON (usp.id)
    usp.id as pool_id,
    esp.id as enhanced_id,
    esp.apr_max,
    esp.duration_months
  FROM user_staking_pools usp
  CROSS JOIN enhanced_staking_pools esp
  WHERE esp.token_type = usp.pool_type
    AND esp.status = 'active'
    AND (
      usp.enhanced_pool_id IS NULL
      OR usp.apy_rate IS NULL
      OR usp.dynamic_apy IS NULL
      OR usp.is_enhanced_pool IS DISTINCT FROM true
    )
  ORDER BY usp.id, ABS(esp.duration_months - COALESCE(usp.stake_duration_months, 3))
)
UPDATE user_staking_pools usp
SET 
  enhanced_pool_id = cp.enhanced_id,
  is_enhanced_pool = true,
  apy_rate = cp.apr_max,
  dynamic_apy = cp.apr_max,
  stake_duration_months = cp.duration_months,
  lock_end_date = now() + (cp.duration_months || ' months')::interval,
  updated_at = now()
FROM closest_pools cp
WHERE usp.id = cp.pool_id;

-- 4) Verify - show summary
SELECT 
  'APY Correction Summary' as status,
  pool_type,
  stake_duration_months,
  COUNT(*) as pools,
  AVG(apy_rate) as avg_apy,
  AVG(dynamic_apy) as avg_dynamic_apy
FROM user_staking_pools
WHERE staked_amount > 0
GROUP BY pool_type, stake_duration_months
ORDER BY pool_type, stake_duration_months;