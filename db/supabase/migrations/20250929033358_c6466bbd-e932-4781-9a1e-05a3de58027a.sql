-- Replace migration with in-place UPDATE to satisfy unique (user_id, pool_type)
CREATE OR REPLACE FUNCTION migrate_users_to_enhanced_pools()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  r RECORD;
  target_enhanced_pool uuid;
  migrated_count integer := 0;
  skipped_count integer := 0;
  details jsonb := '[]'::jsonb;
BEGIN
  -- Start log
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'enhanced_pool_migration_started',
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  FOR r IN
    SELECT *
    FROM user_staking_pools
    WHERE is_enhanced_pool = false
      AND staked_amount > 0
  LOOP
    -- Find a default 3-month enhanced pool matching token type
    SELECT id INTO target_enhanced_pool
    FROM enhanced_staking_pools
    WHERE token_type = r.pool_type
      AND duration_months = 3
      AND status = 'active'
    LIMIT 1;

    IF target_enhanced_pool IS NULL THEN
      skipped_count := skipped_count + 1;
      details := details || jsonb_build_object(
        'user_id', r.user_id,
        'pool_type', r.pool_type,
        'action', 'skipped_no_target_pool'
      );
      CONTINUE;
    END IF;

    -- In-place update to avoid unique constraint violation
    UPDATE user_staking_pools
    SET 
      is_enhanced_pool = true,
      enhanced_pool_id = target_enhanced_pool,
      stake_duration_months = COALESCE(stake_duration_months, 3),
      lock_end_date = COALESCE(lock_end_date, (now() + make_interval(months => COALESCE(stake_duration_months, 3)))),
      original_stake_amount = COALESCE(original_stake_amount, r.staked_amount),
      dynamic_apy = COALESCE(dynamic_apy, apy_rate),
      network_efficiency = COALESCE(network_efficiency, 1.0),
      updated_at = now()
    WHERE id = r.id;

    migrated_count := migrated_count + 1;
    details := details || jsonb_build_object(
      'user_id', r.user_id,
      'pool_type', r.pool_type,
      'action', 'updated_in_place',
      'enhanced_pool_id', target_enhanced_pool
    );
  END LOOP;

  -- Completion log
  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
    auth.uid(),
    'enhanced_pool_migration_completed',
    'user_staking_pools',
    jsonb_build_object(
      'migrated', migrated_count,
      'skipped', skipped_count,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'migrated', migrated_count,
    'skipped', skipped_count,
    'details', details,
    'timestamp', now()
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'timestamp', now()
  );
END;
$$;