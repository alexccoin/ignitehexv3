-- Update admin_correct_voucher_tokens to use $0.005/STR vesting rate (March 2026)
-- HISTORY: Previously used $0.00911/STR. Changed to $0.005/STR for March 1-15, 2026 promotional vesting period.
-- CCOS remains at $9/token, ARSS remains at $0.00911/token.

CREATE OR REPLACE FUNCTION public.admin_correct_voucher_tokens(voucher_id_param uuid, admin_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  voucher_record voucher_redemptions%ROWTYPE;
  correct_amount numeric;
  current_balance numeric;
  difference numeric;
  new_balance numeric;
  usd_amount numeric;
  token_type_val text;
  result jsonb;
BEGIN
  -- Verify admin permissions
  IF NOT is_admin(admin_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Admin privileges required'
    );
  END IF;

  -- Get voucher details
  SELECT * INTO voucher_record
  FROM voucher_redemptions
  WHERE id = voucher_id_param;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Voucher not found'
    );
  END IF;

  token_type_val := lower(voucher_record.token_type);

  -- Extract USD amount from package_type string (e.g., "Foundation ($2500) ≈ ..." or "Foundation ($2,500) ≈ ...")
  usd_amount := NULL;
  
  -- Try to extract from standard format
  IF voucher_record.package_type ~ '\$([0-9,]+)' THEN
    usd_amount := replace(substring(voucher_record.package_type from '\$([0-9,]+)'), ',', '')::numeric;
  END IF;
  
  -- Fallback: extract from legacy formats like "STR-BASIC-2500"
  IF usd_amount IS NULL THEN
    IF voucher_record.package_type ~ '(2500|5000|10000|25000|50000|100000)' THEN
      usd_amount := substring(voucher_record.package_type from '(2500|5000|10000|25000|50000|100000)')::numeric;
    END IF;
  END IF;

  IF usd_amount IS NULL OR usd_amount <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cannot determine USD amount from package type: ' || voucher_record.package_type
    );
  END IF;

  -- Calculate correct amount based on token type and current rates
  -- STR: $0.005/token (March 2026 vesting rate)
  -- CCOS: $9/token
  -- ARSS: $0.00911/token
  IF token_type_val = 'str' OR token_type_val = 'str_stable' THEN
    correct_amount := round(usd_amount / 0.005, 2);
  ELSIF token_type_val = 'ccos' THEN
    correct_amount := round(usd_amount / 9.0, 2);
  ELSIF token_type_val = 'arss' THEN
    correct_amount := round(usd_amount / 0.00911, 2);
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Unknown token type: ' || voucher_record.token_type
    );
  END IF;

  -- Calculate difference
  difference := correct_amount - COALESCE(voucher_record.credited_amount, 0);
  
  -- If no correction needed
  IF ABS(difference) < 0.01 THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Token amount is already correct',
      'correction_needed', false
    );
  END IF;

  -- Initialize user staking pools if they don't exist
  PERFORM initialize_user_staking_pools(voucher_record.user_id);

  -- Get current balance
  SELECT balance INTO current_balance
  FROM user_staking_pools
  WHERE user_id = voucher_record.user_id AND pool_type = token_type_val;
  
  IF current_balance IS NULL THEN
    current_balance := 0;
  END IF;

  new_balance := current_balance + difference;

  -- Update the pool balance
  UPDATE user_staking_pools
  SET 
    balance = new_balance,
    updated_at = now()
  WHERE user_id = voucher_record.user_id AND pool_type = token_type_val;

  -- Update voucher record
  UPDATE voucher_redemptions
  SET 
    credited_amount = correct_amount,
    updated_at = now()
  WHERE id = voucher_id_param;

  -- Log the correction transaction
  INSERT INTO arss_transactions (
    user_id,
    amount,
    transaction_type,
    source_type,
    description,
    status
  ) VALUES (
    voucher_record.user_id,
    difference,
    'voucher_correction',
    'admin_correction',
    'Token amount correction ($0.005/STR rate): ' || voucher_record.package_type || ' (' || 
    CASE WHEN difference > 0 THEN '+' ELSE '' END || difference::text || ')',
    'completed'
  );

  -- Log security audit
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details
  ) VALUES (
    admin_user_id,
    'voucher_token_correction',
    'voucher_redemptions',
    voucher_id_param::text,
    jsonb_build_object(
      'target_user', voucher_record.user_id,
      'package_type', voucher_record.package_type,
      'token_type', voucher_record.token_type,
      'usd_amount', usd_amount,
      'previous_amount', voucher_record.credited_amount,
      'corrected_amount', correct_amount,
      'difference', difference,
      'new_balance', new_balance,
      'rate_used', CASE 
        WHEN token_type_val IN ('str', 'str_stable') THEN '0.005'
        WHEN token_type_val = 'ccos' THEN '9.0'
        WHEN token_type_val = 'arss' THEN '0.00911'
      END
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'corrected_amount', correct_amount,
    'difference', difference,
    'new_balance', new_balance,
    'correction_needed', true,
    'rate_used', CASE 
      WHEN token_type_val IN ('str', 'str_stable') THEN '0.005'
      WHEN token_type_val = 'ccos' THEN '9.0'
      WHEN token_type_val = 'arss' THEN '0.00911'
    END
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;