-- Fix search_path security warning for correct_voucher_amount function
CREATE OR REPLACE FUNCTION correct_voucher_amount(
  p_voucher_id UUID,
  p_corrected_amount NUMERIC,
  p_correction_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_voucher RECORD;
  v_admin_id UUID;
  v_result JSONB;
BEGIN
  -- Get admin user ID
  v_admin_id := auth.uid();
  
  -- Verify admin role
  IF NOT has_role(v_admin_id, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Only admins can correct voucher amounts';
  END IF;
  
  -- Get current voucher details
  SELECT * INTO v_voucher
  FROM voucher_redemptions
  WHERE id = p_voucher_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voucher not found';
  END IF;
  
  -- Insert correction history
  INSERT INTO voucher_corrections (
    voucher_id,
    user_id,
    full_name,
    email_address,
    token_type,
    package_type,
    previous_amount,
    corrected_amount,
    difference,
    correction_type,
    correction_reason,
    corrected_by
  ) VALUES (
    p_voucher_id,
    v_voucher.user_id,
    v_voucher.full_name,
    v_voucher.email_address,
    v_voucher.token_type,
    v_voucher.package_type,
    COALESCE(v_voucher.credited_amount, 0),
    p_corrected_amount,
    p_corrected_amount - COALESCE(v_voucher.credited_amount, 0),
    'manual',
    p_correction_reason,
    v_admin_id
  );
  
  -- Update voucher
  UPDATE voucher_redemptions
  SET 
    credited_amount = p_corrected_amount,
    updated_at = NOW()
  WHERE id = p_voucher_id;
  
  -- Return result
  v_result := jsonb_build_object(
    'success', true,
    'voucher_id', p_voucher_id,
    'previous_amount', COALESCE(v_voucher.credited_amount, 0),
    'corrected_amount', p_corrected_amount,
    'difference', p_corrected_amount - COALESCE(v_voucher.credited_amount, 0)
  );
  
  RETURN v_result;
END;
$$;