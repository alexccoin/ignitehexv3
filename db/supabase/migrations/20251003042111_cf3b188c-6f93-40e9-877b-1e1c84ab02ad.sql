-- Drop existing function if it exists
DROP FUNCTION IF EXISTS public.process_staking_request(uuid, boolean, text);

-- Create function to process staking requests (approve/reject)
CREATE OR REPLACE FUNCTION public.process_staking_request(
  request_id uuid,
  approve boolean,
  admin_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  request_record RECORD;
  result jsonb;
  duration_months INTEGER;
BEGIN
  -- Check admin permissions
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;

  -- Get the staking request
  SELECT * INTO request_record
  FROM staking_requests
  WHERE id = request_id AND status = 'pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Staking request not found or already processed'
    );
  END IF;

  IF approve THEN
    -- Extract duration from description if present
    BEGIN
      SELECT (regexp_match(request_record.description, 'Lock Period: (\d+) months'))[1]::INTEGER
      INTO duration_months;
      
      IF duration_months IS NULL THEN
        duration_months := 3; -- Default to 3 months
      END IF;
    EXCEPTION WHEN OTHERS THEN
      duration_months := 3;
    END;

    IF request_record.request_type = 'stake' THEN
      -- Process stake request using enhanced staking
      SELECT * INTO result FROM distribute_enhanced_rewards(
        user_id_param := request_record.user_id,
        token_type_param := request_record.pool_type,
        amount := request_record.amount,
        duration_months_param := duration_months,
        network_efficiency_param := 1.0
      );

      -- Update request status
      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        processed_by = auth.uid(),
        admin_notes = COALESCE(admin_notes, 'Approved and processed')
      WHERE id = request_id;

    ELSIF request_record.request_type = 'unstake' THEN
      -- Process unstake request
      UPDATE user_staking_pools
      SET 
        staked_amount = GREATEST(0, staked_amount - request_record.amount),
        balance = GREATEST(0, balance - request_record.amount),
        updated_at = now()
      WHERE user_id = request_record.user_id 
      AND pool_type = request_record.pool_type
      AND staked_amount >= request_record.amount;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient staked balance for unstaking';
      END IF;

      -- Update request status
      UPDATE staking_requests
      SET 
        status = 'approved',
        processed_at = now(),
        processed_by = auth.uid(),
        admin_notes = COALESCE(admin_notes, 'Unstake approved')
      WHERE id = request_id;
    END IF;
  ELSE
    -- Reject the request
    UPDATE staking_requests
    SET 
      status = 'rejected',
      processed_at = now(),
      processed_by = auth.uid(),
      admin_notes = COALESCE(admin_notes, 'Rejected by admin')
    WHERE id = request_id;
  END IF;

  -- Log the action
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details
  ) VALUES (
    auth.uid(),
    CASE WHEN approve THEN 'staking_request_approved' ELSE 'staking_request_rejected' END,
    'staking_requests',
    request_id::text,
    jsonb_build_object(
      'target_user', request_record.user_id,
      'pool_type', request_record.pool_type,
      'request_type', request_record.request_type,
      'amount', request_record.amount,
      'admin_notes', admin_notes
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', CASE WHEN approve THEN 'Staking request approved' ELSE 'Staking request rejected' END
  );

EXCEPTION WHEN OTHERS THEN
  -- Log error
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    auth.uid(),
    'staking_request_processing_failed',
    'staking_requests',
    jsonb_build_object(
      'request_id', request_id,
      'error', SQLERRM
    )
  );

  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;