-- Create function to correct voucher credits for specific users
CREATE OR REPLACE FUNCTION public.correct_voucher_credits_batch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  correction_record RECORD;
  corrections_applied jsonb := '[]'::jsonb;
  total_corrections INTEGER := 0;
BEGIN
  -- Log the start of batch corrections
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'batch_voucher_correction_started', 
    'voucher_redemptions',
    jsonb_build_object('timestamp', now())
  );

  -- Remove excess voucher credits for users with too many
  -- Daniel Meyer: Remove 1 extra $2,500 voucher
  UPDATE user_staking_pools 
  SET balance = balance - 274401.67, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'danielmeyer69@live.de')
  AND pool_type = 'str' AND balance >= 274401.67;
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, -274401.67, 'voucher_correction', 'admin_correction',
         'Removed excess $2,500 voucher credit', 'completed'
  FROM user_profiles WHERE email_address = 'danielmeyer69@live.de';

  -- Fabian Dobschat: Remove 1 extra $2,500 voucher
  UPDATE user_staking_pools 
  SET balance = balance - 274401.67, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'mail@fab-consult.com')
  AND pool_type = 'str' AND balance >= 274401.67;
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, -274401.67, 'voucher_correction', 'admin_correction',
         'Removed excess $2,500 voucher credit', 'completed'
  FROM user_profiles WHERE email_address = 'mail@fab-consult.com';

  -- Marcus Staudenmeyer: Remove 2 extra $2,500 vouchers
  UPDATE user_staking_pools 
  SET balance = balance - 548803.34, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'marcus.staudenmeyer@web.de')
  AND pool_type = 'str' AND balance >= 548803.34;
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, -548803.34, 'voucher_correction', 'admin_correction',
         'Removed 2 excess $2,500 voucher credits', 'completed'
  FROM user_profiles WHERE email_address = 'marcus.staudenmeyer@web.de';

  -- Thomas Behr: Remove 2 extra $2,500 vouchers
  UPDATE user_staking_pools 
  SET balance = balance - 548803.34, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'sourcelessteamgermany@proton.me')
  AND pool_type = 'str' AND balance >= 548803.34;
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, -548803.34, 'voucher_correction', 'admin_correction',
         'Removed 2 excess $2,500 voucher credits', 'completed'
  FROM user_profiles WHERE email_address = 'sourcelessteamgermany@proton.me';

  -- Thomas Levy: Remove 1 extra $2,500 voucher
  UPDATE user_staking_pools 
  SET balance = balance - 274401.67, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'tlevy51@gmail.com')
  AND pool_type = 'str' AND balance >= 274401.67;
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, -274401.67, 'voucher_correction', 'admin_correction',
         'Removed excess $2,500 voucher credit', 'completed'
  FROM user_profiles WHERE email_address = 'tlevy51@gmail.com';

  -- Add missing voucher credits
  -- Christopher Grebe: Add 1 missing $2,500 voucher
  PERFORM initialize_user_staking_pools((SELECT user_id FROM user_profiles WHERE email_address = 'grebe.christopher@gmail.com'));
  
  UPDATE user_staking_pools 
  SET balance = balance + 274401.67, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'grebe.christopher@gmail.com')
  AND pool_type = 'str';
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, 274401.67, 'voucher_correction', 'admin_correction',
         'Added missing $2,500 voucher credit', 'completed'
  FROM user_profiles WHERE email_address = 'grebe.christopher@gmail.com';

  -- Martin Trafelet: Add missing $5,000 voucher
  PERFORM initialize_user_staking_pools((SELECT user_id FROM user_profiles WHERE email_address = 'nicolerace81@gmail.com'));
  
  UPDATE user_staking_pools 
  SET balance = balance + 548803.34, updated_at = now()
  WHERE user_id = (SELECT user_id FROM user_profiles WHERE email_address = 'nicolerace81@gmail.com')
  AND pool_type = 'str';
  
  INSERT INTO arss_transactions (user_id, amount, transaction_type, source_type, description, status)
  SELECT user_id, 548803.34, 'voucher_correction', 'admin_correction',
         'Added missing $5,000 voucher credit', 'completed'
  FROM user_profiles WHERE email_address = 'nicolerace81@gmail.com';

  total_corrections := 7;

  -- Log the completion
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    auth.uid(), 
    'batch_voucher_correction_completed', 
    'voucher_redemptions',
    jsonb_build_object(
      'total_corrections', total_corrections,
      'timestamp', now()
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_corrections', total_corrections,
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