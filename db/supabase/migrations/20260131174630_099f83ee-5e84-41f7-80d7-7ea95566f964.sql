
-- Sync seed_str_applications.credited_amount with actual user_staking_pools balances
-- This fixes the data inconsistency where pools were created but application credited_amount wasn't updated

-- For each user that has:
-- 1. A seed_str_application with credited_amount = 0 or NULL
-- 2. An existing STR staking pool with balance > 0
-- Update the application's credited_amount to match the pool's staked_amount

UPDATE seed_str_applications s
SET 
  credited_amount = p.staked_amount,
  credited_at = COALESCE(s.credited_at, p.created_at)
FROM (
  SELECT DISTINCT ON (user_id) 
    user_id, 
    staked_amount,
    created_at
  FROM user_staking_pools 
  WHERE pool_type = 'str' 
    AND staked_amount > 0
  ORDER BY user_id, created_at ASC
) p
WHERE s.user_id = p.user_id
  AND s.status IN ('approved', 'verified')
  AND s.payment_status = 'payment_verified'
  AND (s.credited_amount IS NULL OR s.credited_amount = 0)
  AND s.id = (
    -- Only update the OLDEST application for each user (source of truth per memory)
    SELECT id FROM seed_str_applications s2 
    WHERE s2.user_id = s.user_id 
      AND s2.status IN ('approved', 'verified')
      AND s2.payment_status = 'payment_verified'
    ORDER BY s2.created_at ASC 
    LIMIT 1
  );
