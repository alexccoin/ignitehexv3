-- Create function to fix missing transaction records for voucher redemptions
-- Only creates ARSS transactions for SASP and Sourceless, not for other token types
CREATE OR REPLACE FUNCTION fix_missing_voucher_transaction_records()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  voucher_record RECORD;
  fixed_count INTEGER := 0;
  skipped_count INTEGER := 0;
  fix_summary jsonb := '[]'::jsonb;
  fix_record jsonb;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Find approved voucher redemptions that are marked as credited but don't have transaction records
  FOR voucher_record IN
    SELECT 
      vr.id,
      vr.user_id,
      vr.token_type,
      vr.credited_amount,
      vr.credited_at,
      vr.package_type,
      vr.full_name
    FROM voucher_redemptions vr
    WHERE vr.status = 'approved'
    AND vr.tokens_credited = true
    AND vr.credited_amount > 0
    AND NOT EXISTS (
      SELECT 1 FROM arss_transactions at
      WHERE at.user_id = vr.user_id
      AND at.source_type = 'voucher_redemption'
      AND at.source_id = vr.id
    )
    ORDER BY vr.credited_at
  LOOP
    -- Only create ARSS transaction records for SASP and Sourceless vouchers
    -- For STR, CCOS, and other tokens, skip creating arss_transactions
    IF voucher_record.package_type LIKE '%sasp%' OR voucher_record.package_type LIKE '%sourceless%' THEN
      -- Create the missing transaction record for ARSS-related vouchers
      INSERT INTO arss_transactions (
        user_id,
        amount,
        transaction_type,
        source_type,
        source_id,
        description,
        status,
        created_at
      ) VALUES (
        voucher_record.user_id,
        voucher_record.credited_amount,
        'credit',
        'voucher_redemption',
        voucher_record.id,
        'Voucher redemption: ' || voucher_record.package_type || ' (' || voucher_record.full_name || ')',
        'completed',
        COALESCE(voucher_record.credited_at, now())
      );
      
      fixed_count := fixed_count + 1;
      
      fix_record := jsonb_build_object(
        'voucher_id', voucher_record.id,
        'user_id', voucher_record.user_id,
        'token_type', voucher_record.token_type,
        'amount', voucher_record.credited_amount,
        'package_type', voucher_record.package_type,
        'action', 'transaction_created'
      );
    ELSE
      -- Skip creating ARSS transaction for non-ARSS tokens (STR, CCOS, etc.)
      skipped_count := skipped_count + 1;
      
      fix_record := jsonb_build_object(
        'voucher_id', voucher_record.id,
        'user_id', voucher_record.user_id,
        'token_type', voucher_record.token_type,
        'amount', voucher_record.credited_amount,
        'package_type', voucher_record.package_type,
        'action', 'skipped_non_arss_token'
      );
    END IF;
    
    fix_summary := fix_summary || fix_record;
  END LOOP;

  -- Log the operation
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'voucher_transaction_records_fixed', 
    'arss_transactions',
    jsonb_build_object(
      'fixed_count', fixed_count,
      'skipped_count', skipped_count,
      'fix_summary', fix_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'fixed_count', fixed_count,
    'skipped_count', skipped_count,
    'message', 'Fixed ' || fixed_count || ' missing ARSS transaction records, skipped ' || skipped_count || ' non-ARSS vouchers',
    'fix_summary', fix_summary,
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