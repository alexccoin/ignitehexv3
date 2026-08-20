DO $$
DECLARE
  v RECORD;
  correct_amt NUMERIC;
  diff NUMERIC;
  lock_end TIMESTAMPTZ := (NOW() + INTERVAL '60 days');
  precex_map JSONB := '{
    "Launch Gate Voucher ($250) ≈ 166666 STR": 166666,
    "Market Spark Voucher ($500) ≈ 333333 STR": 333333,
    "Exchange Lift Voucher ($750) ≈ 500000 STR": 500000,
    "Listing Prime Voucher ($1000) ≈ 666666 STR": 666666,
    "Access Surge Voucher ($1250) ≈ 833333 STR": 833333,
    "Exchange Anchor Voucher ($1500) ≈ 1000000 STR": 1000000,
    "Listing Force Voucher ($2000) ≈ 1333333 STR": 1333333,
    "Priority Wave Voucher ($2500) ≈ 1666666 STR": 1666666,
    "Market Rise Voucher ($5000) ≈ 3333333 STR": 3333333,
    "Exchange Elite Voucher ($10000) ≈ 6666666 STR": 6666666,
    "Listing Vanguard Voucher ($25000) ≈ 16666666 STR": 16666666,
    "Market Titan Voucher ($50000) ≈ 33333333 STR": 33333333,
    "Exchange Crown Voucher ($100000) ≈ 66666666 STR": 66666666
  }'::JSONB;
BEGIN
  FOR v IN
    SELECT id, user_id, package_type, credited_amount, full_name, email_address
    FROM public.voucher_redemptions
    WHERE token_type = 'str'
      AND status = 'approved'
      AND tokens_credited = true
      AND credited_at >= NOW() - INTERVAL '3 days'
      AND precex_map ? package_type
  LOOP
    correct_amt := (precex_map ->> v.package_type)::NUMERIC;
    diff := correct_amt - COALESCE(v.credited_amount, 0);

    IF diff <= 0.01 THEN
      CONTINUE;
    END IF;

    -- Additive top-up: new 60-day vesting pool with the missing diff
    INSERT INTO public.user_staking_pools (
      user_id, pool_type, balance, staked_amount, original_stake_amount,
      stake_duration_months, lock_end_date, apy_rate, dynamic_apy,
      rewards_earned, status, last_reward_date, admin_notes
    ) VALUES (
      v.user_id, 'str', diff, diff, diff,
      3, lock_end, 0, 0,
      0, 'active', CURRENT_DATE,
      'precex_str_voucher_correction_topup_2026_05_09: ' || v.package_type
        || ' (was ' || COALESCE(v.credited_amount, 0)::TEXT
        || ' → corrected to ' || correct_amt::TEXT || ', +' || diff::TEXT || ')'
    );

    -- Update voucher row to reflect canonical credited amount
    UPDATE public.voucher_redemptions
    SET credited_amount = correct_amt,
        admin_notes = COALESCE(admin_notes, '')
          || ' | precex_correction_2026_05_09 +' || diff::TEXT,
        updated_at = NOW()
    WHERE id = v.id;

    -- Audit transaction
    INSERT INTO public.arss_transactions (
      user_id, amount, currency, transaction_type, source_type, source_id,
      description, status
    ) VALUES (
      v.user_id, diff, 'str', 'voucher_correction', 'precex_voucher_correction', v.id,
      'Pre-CEX STR voucher correction (' || v.package_type || '): '
        || COALESCE(v.credited_amount, 0)::TEXT || ' → ' || correct_amt::TEXT
        || ' (+' || diff::TEXT || ')',
      'completed'
    );
  END LOOP;
END $$;