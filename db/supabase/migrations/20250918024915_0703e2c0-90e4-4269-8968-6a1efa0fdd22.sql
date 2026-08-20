-- Fix STR balance discrepancies for all users
-- This function will recalculate and correct user STR balances based on voucher redemptions and manual credits

CREATE OR REPLACE FUNCTION public.fix_str_balance_discrepancies()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  expected_balance NUMERIC;
  current_balance NUMERIC;
  balance_difference NUMERIC;
  total_fixes INTEGER := 0;
  fixes_summary jsonb := '[]'::jsonb;
  fix_record jsonb;
BEGIN
  -- Log the start of balance fixes
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'str_balance_fix_started', 
    'user_staking_pools',
    jsonb_build_object('timestamp', now())
  );

  -- Loop through all users who have voucher redemptions or manual credits
  FOR user_record IN
    SELECT 
      up.user_id,
      up.full_name, 
      up.email_address,
      COALESCE(usp.balance, 0) as current_str_balance,
      COALESCE(SUM(vr.credited_amount), 0) as total_voucher_credits,
      COALESCE(SUM(CASE WHEN at.transaction_type = 'manual_credit' THEN at.amount ELSE 0 END), 0) as total_manual_credits,
      COALESCE(SUM(CASE WHEN at.transaction_type = 'voucher_correction' THEN at.amount ELSE 0 END), 0) as total_corrections,
      COALESCE(usp.rewards_earned, 0) as total_rewards,
      COALESCE(usp.staked_amount, 0) as staked_amount
    FROM user_profiles up
    LEFT JOIN user_staking_pools usp ON up.user_id = usp.user_id AND usp.pool_type = 'str'
    LEFT JOIN voucher_redemptions vr ON up.user_id = vr.user_id AND vr.status = 'approved' AND vr.token_type = 'str'
    LEFT JOIN arss_transactions at ON up.user_id = at.user_id AND at.transaction_type IN ('manual_credit', 'voucher_correction')
    WHERE (vr.id IS NOT NULL OR at.id IS NOT NULL)
    GROUP BY up.user_id, up.full_name, up.email_address, usp.balance, usp.rewards_earned, usp.staked_amount
  LOOP
    -- Calculate expected balance: voucher credits + manual credits + corrections + rewards + base 1000 ARSS welcome bonus
    expected_balance := user_record.total_voucher_credits + user_record.total_manual_credits + user_record.total_corrections + user_record.total_rewards + 1000;
    current_balance := user_record.current_str_balance;
    balance_difference := expected_balance - current_balance;

    -- Only fix if there's a significant discrepancy (more than 1 STR)
    IF ABS(balance_difference) > 1 THEN
      -- Initialize user staking pools if they don't exist
      PERFORM initialize_user_staking_pools(user_record.user_id);
      
      -- Update the STR pool balance to the correct amount
      UPDATE user_staking_pools
      SET 
        balance = expected_balance,
        updated_at = now()
      WHERE user_id = user_record.user_id AND pool_type = 'str';

      -- Create a correction transaction if needed
      IF balance_difference != 0 THEN
        INSERT INTO arss_transactions (
          user_id,
          amount,
          transaction_type,
          source_type,
          description,
          status
        ) VALUES (
          user_record.user_id,
          balance_difference,
          'balance_correction',
          'system_fix',
          'STR balance correction: ' || user_record.full_name || ' (' || 
          CASE WHEN balance_difference > 0 THEN '+' ELSE '' END || balance_difference::text || ' STR)',
          'completed'
        );
      END IF;

      -- Track this fix
      fix_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'full_name', user_record.full_name,
        'email_address', user_record.email_address,
        'previous_balance', current_balance,
        'corrected_balance', expected_balance,
        'difference', balance_difference,
        'voucher_credits', user_record.total_voucher_credits,
        'manual_credits', user_record.total_manual_credits,
        'corrections', user_record.total_corrections,
        'rewards', user_record.total_rewards
      );
      
      fixes_summary := fixes_summary || fix_record;
      total_fixes := total_fixes + 1;
    END IF;
  END LOOP;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'str_balance_fix_completed', 
    'user_staking_pools',
    jsonb_build_object(
      'total_fixes', total_fixes,
      'fixes_summary', fixes_summary,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_fixes', total_fixes,
    'fixes_applied', fixes_summary,
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