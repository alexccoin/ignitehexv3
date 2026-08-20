-- Re-approve Joseph Schemberger's voucher redemption and credit tokens
DO $$
DECLARE
  v_user_id uuid := '48a4a2be-2fc4-4f48-9bcb-6c23d152b52e';
  v_voucher_id uuid := 'ddeee829-43d0-483f-94f5-0626a0d11b3e';
  v_credit_amount numeric := 274401.67;
BEGIN
  -- Update voucher redemption status to approved
  UPDATE voucher_redemptions
  SET 
    status = 'approved',
    tokens_credited = true,
    credited_amount = v_credit_amount,
    credited_at = now(),
    admin_notes = 'Re-approved after accidental rejection - manually corrected by admin'
  WHERE id = v_voucher_id;

  -- Check if user has STR staking pool, if not create it
  INSERT INTO user_staking_pools (user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate)
  VALUES (v_user_id, 'str', v_credit_amount, v_credit_amount, 0, 11.0)
  ON CONFLICT (user_id, pool_type, stake_duration_months)
  DO UPDATE SET
    balance = user_staking_pools.balance + v_credit_amount,
    staked_amount = user_staking_pools.staked_amount + v_credit_amount,
    updated_at = now();

  -- Log the transaction
  INSERT INTO arss_transactions (
    user_id,
    amount,
    transaction_type,
    source_type,
    description,
    status
  ) VALUES (
    v_user_id,
    v_credit_amount,
    'credit',
    'voucher_redemption',
    'Foundation voucher re-approved: Joseph Schemberger - corrected rejection',
    'completed'
  );
END $$;