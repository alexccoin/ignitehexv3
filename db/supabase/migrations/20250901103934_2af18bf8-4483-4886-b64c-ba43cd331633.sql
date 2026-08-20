-- Add RLS policy to allow admins to create correction transactions for any user
CREATE POLICY "Admins can create correction transactions for any user"
ON arss_transactions
FOR INSERT
TO authenticated
WITH CHECK (
  is_admin(auth.uid()) AND 
  transaction_type IN ('voucher_correction', 'admin_correction', 'manual_credit')
);

-- Create function to correct voucher amounts with proper admin permissions
CREATE OR REPLACE FUNCTION admin_correct_voucher_tokens(
  voucher_id_param uuid,
  admin_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  voucher_record voucher_redemptions%ROWTYPE;
  correct_amount numeric;
  current_balance numeric;
  difference numeric;
  new_balance numeric;
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

  -- Map package types to correct STR token amounts
  CASE voucher_record.package_type
    -- New naming convention
    WHEN 'Foundation ($2,500) ≈ 274,401.67 STR' THEN correct_amount := 274401.67;
    WHEN 'Pioneer ($5,000) ≈ 548,803.34 STR' THEN correct_amount := 548803.34;
    WHEN 'Innovator''s ($10,000) ≈ 1,097,606.69 STR' THEN correct_amount := 1097606.69;
    WHEN 'Architect''s ($25,000) ≈ 2,744,016.72 STR' THEN correct_amount := 2744016.72;
    WHEN 'Network Builder''s ($50,000) ≈ 5,488,033.44 STR' THEN correct_amount := 5488033.44;
    WHEN 'Quantum Core ($100,000) ≈ 10,976,066.89 STR' THEN correct_amount := 10976066.89;
    
    -- Old naming convention for STR
    WHEN 'STR-BASIC-2500' THEN correct_amount := 274401.67; -- Foundation
    WHEN 'STR-PREMIUM-5000' THEN correct_amount := 548803.34; -- Pioneer
    WHEN 'STR-ELITE-10000' THEN correct_amount := 1097606.69; -- Innovator's
    WHEN 'STR-ENTERPRISE-25000' THEN correct_amount := 2744016.72; -- Architect's
    
    -- Old naming convention for CCOS
    WHEN 'CCOS-STARTER-2500' THEN correct_amount := 274401.67; -- Foundation
    WHEN 'CCOS-PROFESSIONAL-5000' THEN correct_amount := 548803.34; -- Pioneer
    WHEN 'CCOS-BUSINESS-10000' THEN correct_amount := 1097606.69; -- Innovator's
    WHEN 'CCOS-CORPORATE-25000' THEN correct_amount := 2744016.72; -- Architect's
    
    -- Old naming convention for ARSS
    WHEN 'ARSS-AI-2500' THEN correct_amount := 274401.67; -- Foundation
    WHEN 'ARSS-PRO-5000' THEN correct_amount := 548803.34; -- Pioneer
    WHEN 'ARSS-ADVANCED-10000' THEN correct_amount := 1097606.69; -- Innovator's
    WHEN 'ARSS-SUPREME-25000' THEN correct_amount := 2744016.72; -- Architect's
    
    ELSE 
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Invalid package type: ' || voucher_record.package_type
      );
  END CASE;

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
  WHERE user_id = voucher_record.user_id AND pool_type = voucher_record.token_type;
  
  IF current_balance IS NULL THEN
    current_balance := 0;
  END IF;

  new_balance := current_balance + difference;

  -- Update the pool balance
  UPDATE user_staking_pools
  SET 
    balance = new_balance,
    updated_at = now()
  WHERE user_id = voucher_record.user_id AND pool_type = voucher_record.token_type;

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
    'Token amount correction: ' || voucher_record.package_type || ' (' || 
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
      'previous_amount', voucher_record.credited_amount,
      'corrected_amount', correct_amount,
      'difference', difference,
      'new_balance', new_balance
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'corrected_amount', correct_amount,
    'difference', difference,
    'new_balance', new_balance,
    'correction_needed', true
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;