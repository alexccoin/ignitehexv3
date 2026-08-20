
-- Add duration_months column to staking_requests table
ALTER TABLE staking_requests 
ADD COLUMN IF NOT EXISTS duration_months INTEGER;

-- Add constraint to validate duration values
ALTER TABLE staking_requests
ADD CONSTRAINT staking_requests_duration_check 
CHECK (duration_months IN (3, 6, 9, 12, 24, 36, 48));

-- Update submit-staking-request edge function will be done separately
-- For now, backfill existing requests by parsing their descriptions
UPDATE staking_requests
SET duration_months = (regexp_match(coalesce(description,''), 'Lock Period: (\d+) months'))[1]::INTEGER
WHERE duration_months IS NULL 
  AND description IS NOT NULL
  AND description ~ 'Lock Period: \d+ months';

-- Set default to 3 for any that couldn't be parsed
UPDATE staking_requests
SET duration_months = 3
WHERE duration_months IS NULL;

-- Make duration_months NOT NULL after backfill
ALTER TABLE staking_requests
ALTER COLUMN duration_months SET NOT NULL;

-- Update process_staking_request function to use column instead of parsing
CREATE OR REPLACE FUNCTION public.process_staking_request(
  request_id uuid, 
  approve boolean, 
  admin_notes_param text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  request_record RECORD;
  result jsonb;
  admin_user_id uuid;
  target_pool_id uuid;
  target_lock_end timestamptz;
BEGIN
  admin_user_id := auth.uid();
  IF NOT is_admin(admin_user_id) THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;

  -- Fetch the request with duration_months column
  SELECT * INTO request_record
  FROM staking_requests
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Staking request not found or already processed');
  END IF;

  IF approve THEN
    IF request_record.request_type = 'stake' THEN
      BEGIN
        -- Use distribute_enhanced_rewards to create the staking pool
        SELECT * INTO result FROM distribute_enhanced_rewards(
          user_id_param := request_record.user_id,
          token_type_param := request_record.pool_type,
          amount := request_record.amount,
          duration_months_param := request_record.duration_months,
          network_efficiency_param := 1.0
        );
      EXCEPTION WHEN unique_violation THEN
        -- If unique violation, create a NEW separate pool instead of merging
        SELECT esp.id INTO target_pool_id
        FROM enhanced_staking_pools esp
        WHERE esp.token_type = request_record.pool_type
          AND esp.duration_months = request_record.duration_months
          AND esp.status = 'active'
        ORDER BY esp.created_at DESC
        LIMIT 1;

        target_lock_end := now() + (request_record.duration_months || ' months')::interval;

        -- INSERT without ON CONFLICT to create separate pool
        INSERT INTO user_staking_pools (
          user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate,
          stake_duration_months, lock_end_date, is_enhanced_pool, enhanced_pool_id, 
          created_at, updated_at, status
        ) VALUES (
          request_record.user_id, 
          request_record.pool_type, 
          request_record.amount, 
          request_record.amount, 
          0, 
          0,
          request_record.duration_months, 
          target_lock_end, 
          true, 
          target_pool_id, 
          now(), 
          now(),
          'active'
        );

        result := jsonb_build_object('success', true, 'created_new_pool', true);
      END;

      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        approved_by = admin_user_id,
        admin_notes = COALESCE(admin_notes_param, 'Approved and processed')
      WHERE id = request_id;

    ELSIF request_record.request_type = 'unstake' THEN
      -- Unstake from pools matching the duration
      UPDATE user_staking_pools
      SET 
        staked_amount = GREATEST(0, staked_amount - request_record.amount),
        balance = GREATEST(0, balance - request_record.amount),
        updated_at = now()
      WHERE user_id = request_record.user_id 
        AND pool_type = request_record.pool_type
        AND stake_duration_months = request_record.duration_months
        AND staked_amount >= request_record.amount;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient staked balance for unstaking';
      END IF;

      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        approved_by = admin_user_id,
        admin_notes = COALESCE(admin_notes_param, 'Unstake approved')
      WHERE id = request_id;
    END IF;
  ELSE
    UPDATE staking_requests
    SET 
      status = 'rejected',
      processed_at = now(),
      approved_by = admin_user_id,
      admin_notes = COALESCE(admin_notes_param, 'Rejected by admin')
    WHERE id = request_id;
  END IF;

  -- Best-effort audit log
  BEGIN
    INSERT INTO security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      admin_user_id,
      CASE WHEN approve THEN 'approve_staking_request' ELSE 'reject_staking_request' END,
      'staking_request',
      request_id,
      jsonb_build_object(
        'request_type', request_record.request_type,
        'pool_type', request_record.pool_type,
        'amount', request_record.amount,
        'duration_months', request_record.duration_months
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'approved', approve);
END;
$function$;

-- Comment explaining the fix
COMMENT ON COLUMN staking_requests.duration_months IS 
'Duration in months for the staking lock period. Valid values: 3, 6, 9, 12, 24, 36, 48. Previously stored only in description field.';
