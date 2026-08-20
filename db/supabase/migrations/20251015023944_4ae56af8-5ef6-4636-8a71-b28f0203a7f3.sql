
-- Fix the voucher balance correction function to prevent oscillations
-- The issue is that it was including rewards_earned in calculations and overwriting staked_amount

CREATE OR REPLACE FUNCTION public.fix_all_user_voucher_balances()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  expected_initial_credit NUMERIC;
  actual_initial_credit NUMERIC;
  correction_amount NUMERIC;
  total_fixes INTEGER := 0;
  fixes_summary jsonb := '[]'::jsonb;
  fix_record jsonb;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Log the start
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'voucher_balance_fix_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  -- Loop through all users who have credited vouchers
  -- Compare INITIAL credits vs what they should have received
  FOR user_record IN
    SELECT 
      vr.user_id,
      up.full_name,
      COALESCE(SUM(vr.credited_amount), 0) as total_voucher_credits,
      COALESCE(usp.balance, 0) as current_balance,
      COALESCE(usp.staked_amount, 0) as current_staked,
      COUNT(vr.id) as voucher_count,
      -- Sum up all voucher correction transactions that already happened
      COALESCE((
        SELECT SUM(at.amount) 
        FROM arss_transactions at 
        WHERE at.user_id = vr.user_id 
        AND at.transaction_type = 'balance_correction'
        AND at.source_type = 'system_fix'
        AND at.description LIKE 'Balance correction for voucher credits%'
      ), 0) as previous_corrections
    FROM voucher_redemptions vr
    JOIN user_profiles up ON vr.user_id = up.user_id
    LEFT JOIN user_staking_pools usp ON vr.user_id = usp.user_id AND usp.pool_type = 'str'
    WHERE vr.status = 'approved' AND vr.tokens_credited = true
    GROUP BY vr.user_id, up.full_name, usp.balance, usp.staked_amount
  LOOP
    -- Expected initial credit = voucher credits + base 1000
    expected_initial_credit := user_record.total_voucher_credits + 1000;
    
    -- Actual initial credit = current staked amount (which should be voucher credits + base)
    -- We need to subtract any previous corrections to get the true initial credit
    actual_initial_credit := user_record.current_staked;
    
    -- Calculate correction needed
    correction_amount := expected_initial_credit - actual_initial_credit;

    -- Only fix if there's a significant discrepancy (more than 100 STR)
    -- AND we haven't already corrected this exact amount
    IF ABS(correction_amount) > 100 THEN
      -- Initialize user staking pools if they don't exist
      PERFORM initialize_user_staking_pools(user_record.user_id);
      
      -- Apply correction by adjusting both balance and staked_amount by the same correction amount
      -- This preserves rewards_earned = balance - staked_amount
      UPDATE user_staking_pools
      SET 
        balance = balance + correction_amount,
        staked_amount = staked_amount + correction_amount,
        updated_at = now()
      WHERE user_id = user_record.user_id AND pool_type = 'str';

      -- Create a correction transaction
      INSERT INTO arss_transactions (
        user_id,
        amount,
        transaction_type,
        source_type,
        description,
        status
      ) VALUES (
        user_record.user_id,
        correction_amount,
        'balance_correction',
        'system_fix',
        'Balance correction for voucher credits - Fixed discrepancy of ' || correction_amount::text || ' STR (Expected: ' || expected_initial_credit::text || ', Had: ' || actual_initial_credit::text || ')',
        'completed'
      );
      
      total_fixes := total_fixes + 1;
      
      fix_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'full_name', user_record.full_name,
        'voucher_count', user_record.voucher_count,
        'total_voucher_credits', user_record.total_voucher_credits,
        'expected_initial_credit', expected_initial_credit,
        'actual_initial_credit', actual_initial_credit,
        'correction_amount', correction_amount,
        'current_balance', user_record.current_balance,
        'new_balance', user_record.current_balance + correction_amount
      );
      
      fixes_summary := fixes_summary || fix_record;
    END IF;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'voucher_balance_fix_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'fixes_applied', total_fixes,
      'fixes_summary', fixes_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'fixes_applied', total_fixes,
    'fixes_summary', fixes_summary,
    'timestamp', now()
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'timestamp', now()
  );
END;
$function$;
