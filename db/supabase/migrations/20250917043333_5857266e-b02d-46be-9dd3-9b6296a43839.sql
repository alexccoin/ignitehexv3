-- Credit rejected voucher redemptions for specified users
-- This migration will correct the token amounts for rejected vouchers

DO $$
DECLARE
  sonja_user_id uuid := 'aa26c3bf-117c-4a38-aec0-cffcb760afd2';
  konrad_user_id uuid := 'e9cfb4b8-8295-4855-a397-5bdb9973e49d';
  wilhelm_user_id uuid := 'de8ef477-84fa-4717-af05-46bcdca03234';
  foundation_amount numeric := 274401.67;
  current_balance numeric;
BEGIN
  -- Initialize staking pools for all users if they don't exist
  PERFORM initialize_user_staking_pools(sonja_user_id);
  PERFORM initialize_user_staking_pools(konrad_user_id);
  PERFORM initialize_user_staking_pools(wilhelm_user_id);

  -- Credit Sonja Richter (soluxxa@gmail.com)
  -- Update voucher redemption
  UPDATE voucher_redemptions
  SET 
    status = 'approved',
    tokens_credited = true,
    credited_amount = foundation_amount,
    credited_at = now(),
    updated_at = now(),
    admin_notes = 'Manual credit approved - Foundation package tokens'
  WHERE id = 'eb38195e-8923-4b94-b054-dce409fc46e7';

  -- Add tokens to staking pool
  UPDATE user_staking_pools
  SET 
    balance = balance + foundation_amount,
    updated_at = now()
  WHERE user_id = sonja_user_id AND pool_type = 'str';

  -- Log transaction
  INSERT INTO arss_transactions (
    user_id, amount, transaction_type, source_type, description, status
  ) VALUES (
    sonja_user_id, foundation_amount, 'voucher_credit', 'manual_correction',
    'Foundation package credit - Manual approval', 'completed'
  );

  -- Credit Konrad Schmidt (konrad.schmidt60@gmail.com) - rejected voucher from Sept 9
  -- Update voucher redemption
  UPDATE voucher_redemptions
  SET 
    status = 'approved',
    tokens_credited = true,
    credited_amount = foundation_amount,
    credited_at = now(),
    updated_at = now(),
    admin_notes = 'Manual credit approved - Foundation package tokens'
  WHERE id = '891eaa61-2fdd-42ed-914e-5c091a7cf0e8';

  -- Add tokens to staking pool
  UPDATE user_staking_pools
  SET 
    balance = balance + foundation_amount,
    updated_at = now()
  WHERE user_id = konrad_user_id AND pool_type = 'str';

  -- Log transaction
  INSERT INTO arss_transactions (
    user_id, amount, transaction_type, source_type, description, status
  ) VALUES (
    konrad_user_id, foundation_amount, 'voucher_credit', 'manual_correction',
    'Foundation package credit - Manual approval', 'completed'
  );

  -- Credit Wilhelm Buck (buchhaltung-buck@posteo.de)
  -- Update voucher redemption
  UPDATE voucher_redemptions
  SET 
    status = 'approved',
    tokens_credited = true,
    credited_amount = foundation_amount,
    credited_at = now(),
    updated_at = now(),
    admin_notes = 'Manual credit approved - Foundation package tokens'
  WHERE id = '28f00df4-babd-4600-b509-de07eeef58b5';

  -- Add tokens to staking pool
  UPDATE user_staking_pools
  SET 
    balance = balance + foundation_amount,
    updated_at = now()
  WHERE user_id = wilhelm_user_id AND pool_type = 'str';

  -- Log transaction
  INSERT INTO arss_transactions (
    user_id, amount, transaction_type, source_type, description, status
  ) VALUES (
    wilhelm_user_id, foundation_amount, 'voucher_credit', 'manual_correction',
    'Foundation package credit - Manual approval', 'completed'
  );

  -- Log admin action in security audit
  INSERT INTO security_audit_log (
    action, resource_type, details
  ) VALUES (
    'bulk_voucher_credit',
    'voucher_redemptions',
    jsonb_build_object(
      'credited_users', jsonb_build_array(
        jsonb_build_object('email', 'soluxxa@gmail.com', 'name', 'Sonja Richter', 'amount', foundation_amount),
        jsonb_build_object('email', 'konrad.schmidt60@gmail.com', 'name', 'Konrad Schmidt', 'amount', foundation_amount),
        jsonb_build_object('email', 'buchhaltung-buck@posteo.de', 'name', 'Wilhelm Buck', 'amount', foundation_amount)
      ),
      'total_credited', foundation_amount * 3,
      'timestamp', now(),
      'reason', 'Manual voucher credit approval'
    )
  );

END $$;