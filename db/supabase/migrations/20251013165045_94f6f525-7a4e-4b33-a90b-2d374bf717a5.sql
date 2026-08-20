
-- Fix the credit_voucher_tokens function to properly update balances
CREATE OR REPLACE FUNCTION public.credit_voucher_tokens(
  voucher_id uuid,
  user_id_param uuid,
  token_type_param text,
  package_type_param text
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  credit_amount NUMERIC := 0;
  wallet_exists BOOLEAN := false;
BEGIN
  -- Determine credit amount based on package type
  CASE 
    WHEN package_type_param LIKE '%-2500' THEN credit_amount := 2500;
    WHEN package_type_param LIKE '%-5000' THEN credit_amount := 5000;
    WHEN package_type_param LIKE '%-10000' THEN credit_amount := 10000;
    WHEN package_type_param LIKE '%-25000' THEN credit_amount := 25000;
    ELSE credit_amount := 0;
  END CASE;
  
  -- Check if user has existing staking pools for this token type
  SELECT EXISTS(
    SELECT 1 FROM user_staking_pools 
    WHERE user_id = user_id_param AND pool_type = token_type_param
  ) INTO wallet_exists;
  
  -- Initialize staking pools if they don't exist
  IF NOT wallet_exists THEN
    PERFORM initialize_user_staking_pools(user_id_param);
  END IF;
  
  -- Credit the tokens to the appropriate pool
  UPDATE user_staking_pools 
  SET 
    balance = balance + credit_amount,
    staked_amount = staked_amount + credit_amount,
    updated_at = now()
  WHERE user_id = user_id_param AND pool_type = token_type_param;
  
  -- Update voucher redemption record
  UPDATE voucher_redemptions 
  SET 
    tokens_credited = true,
    credited_amount = credit_amount,
    credited_at = now(),
    updated_at = now()
  WHERE id = voucher_id;
  
  -- Create transaction record only for ARSS-related vouchers
  IF token_type_param IN ('str', 'arss') THEN
    INSERT INTO arss_transactions (
      user_id,
      amount,
      transaction_type,
      source_type,
      source_id,
      description,
      status
    ) VALUES (
      user_id_param,
      credit_amount,
      'credit',
      'voucher_redemption',
      voucher_id,
      'Voucher redemption: ' || package_type_param,
      'completed'
    );
  END IF;
  
  RETURN credit_amount;
END;
$function$;

-- Create a function to recalculate and fix all user balances based on voucher credits
CREATE OR REPLACE FUNCTION public.fix_all_user_voucher_balances()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_record RECORD;
  expected_str_balance NUMERIC;
  current_str_balance NUMERIC;
  balance_difference NUMERIC;
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
  FOR user_record IN
    SELECT 
      vr.user_id,
      up.full_name,
      COALESCE(SUM(vr.credited_amount), 0) as total_voucher_credits,
      COALESCE(usp.balance, 0) as current_str_balance,
      COALESCE(usp.rewards_earned, 0) as total_rewards,
      COUNT(vr.id) as voucher_count
    FROM voucher_redemptions vr
    JOIN user_profiles up ON vr.user_id = up.user_id
    LEFT JOIN user_staking_pools usp ON vr.user_id = usp.user_id AND usp.pool_type = 'str'
    WHERE vr.status = 'approved' AND vr.tokens_credited = true
    GROUP BY vr.user_id, up.full_name, usp.balance, usp.rewards_earned
  LOOP
    -- Calculate expected balance: voucher credits + base 1000 ARSS + rewards
    expected_str_balance := user_record.total_voucher_credits + 1000 + user_record.total_rewards;
    current_str_balance := user_record.current_str_balance;
    balance_difference := expected_str_balance - current_str_balance;

    -- Only fix if there's a significant discrepancy (more than 100 STR)
    IF ABS(balance_difference) > 100 THEN
      -- Initialize user staking pools if they don't exist
      PERFORM initialize_user_staking_pools(user_record.user_id);
      
      -- Update the STR pool balance to the correct amount
      UPDATE user_staking_pools
      SET 
        balance = expected_str_balance,
        staked_amount = user_record.total_voucher_credits + 1000,
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
        balance_difference,
        'balance_correction',
        'system_fix',
        'Balance correction for voucher credits - Fixed discrepancy of ' || balance_difference::text,
        'completed'
      );
      
      total_fixes := total_fixes + 1;
      
      fix_record := jsonb_build_object(
        'user_id', user_record.user_id,
        'full_name', user_record.full_name,
        'voucher_count', user_record.voucher_count,
        'total_voucher_credits', user_record.total_voucher_credits,
        'previous_balance', current_str_balance,
        'corrected_balance', expected_str_balance,
        'difference', balance_difference
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
