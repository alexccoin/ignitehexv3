-- Add support for the new pre-CEX listing STR-TOKEN voucher packages
-- Each redeemed voucher creates a dedicated 60-day vesting pool (APY 0%) with the exact token amount

CREATE OR REPLACE FUNCTION public.credit_voucher_tokens(user_id_param uuid, token_type_param text, package_type_param text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  token_amount numeric;
  usd_amount numeric;
  price_per_token numeric;
  token_key text := lower(token_type_param);
  target_pool_id uuid;
  current_staked numeric := 0;
  current_balance numeric := 0;
  voucher_apy numeric := 0;
  new_lock_end timestamptz;
  is_precex_str boolean := false;
BEGIN
  -- Detect new Pre-CEX STR vouchers (60-day vesting, 0% APY, dedicated pool)
  IF token_key = 'str' THEN
    CASE package_type_param
      WHEN 'Launch Gate Voucher ($250) ≈ 166666 STR' THEN token_amount := 166666; is_precex_str := true;
      WHEN 'Market Spark Voucher ($500) ≈ 333333 STR' THEN token_amount := 333333; is_precex_str := true;
      WHEN 'Exchange Lift Voucher ($750) ≈ 500000 STR' THEN token_amount := 500000; is_precex_str := true;
      WHEN 'Listing Prime Voucher ($1000) ≈ 666666 STR' THEN token_amount := 666666; is_precex_str := true;
      WHEN 'Access Surge Voucher ($1250) ≈ 833333 STR' THEN token_amount := 833333; is_precex_str := true;
      WHEN 'Exchange Anchor Voucher ($1500) ≈ 1000000 STR' THEN token_amount := 1000000; is_precex_str := true;
      WHEN 'Listing Force Voucher ($2000) ≈ 1333333 STR' THEN token_amount := 1333333; is_precex_str := true;
      WHEN 'Priority Wave Voucher ($2500) ≈ 1666666 STR' THEN token_amount := 1666666; is_precex_str := true;
      WHEN 'Market Rise Voucher ($5000) ≈ 3333333 STR' THEN token_amount := 3333333; is_precex_str := true;
      WHEN 'Exchange Elite Voucher ($10000) ≈ 6666666 STR' THEN token_amount := 6666666; is_precex_str := true;
      WHEN 'Listing Vanguard Voucher ($25000) ≈ 16666666 STR' THEN token_amount := 16666666; is_precex_str := true;
      WHEN 'Market Titan Voucher ($50000) ≈ 33333333 STR' THEN token_amount := 33333333; is_precex_str := true;
      WHEN 'Exchange Crown Voucher ($100000) ≈ 66666666 STR' THEN token_amount := 66666666; is_precex_str := true;
      ELSE is_precex_str := false;
    END CASE;
  END IF;

  IF is_precex_str THEN
    -- Create dedicated 60-day vesting pool, 0% APY, per voucher
    new_lock_end := NOW() + INTERVAL '60 days';

    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      balance,
      staked_amount,
      original_stake_amount,
      rewards_earned,
      apy_rate,
      dynamic_apy,
      stake_duration_months,
      lock_end_date,
      status,
      admin_notes,
      last_reward_date,
      created_at,
      updated_at
    ) VALUES (
      user_id_param,
      'str',
      token_amount,
      token_amount,
      token_amount,
      0,
      0,
      0,
      3, -- satisfies duration constraint; lock_end_date is the authoritative 60-day lock
      new_lock_end,
      'active',
      'precex_str_voucher_60d_vesting: ' || package_type_param,
      CURRENT_DATE,
      NOW(),
      NOW()
    )
    RETURNING id INTO target_pool_id;

    INSERT INTO arss_transactions (
      user_id, amount, currency, transaction_type, source_type, description, status
    ) VALUES (
      user_id_param, token_amount, 'str', 'voucher_redemption', 'voucher_system',
      'Pre-CEX STR voucher (60d vesting): ' || package_type_param, 'completed'
    );

    RETURN jsonb_build_object(
      'success', true,
      'pool_id', target_pool_id,
      'tokens_credited', token_amount,
      'token_type', 'str',
      'package_type', package_type_param,
      'apy_rate_applied', 0,
      'vesting_days', 60,
      'lock_end_date', new_lock_end
    );
  END IF;

  -- ===== Legacy / standard crediting flow (unchanged) =====
  CASE token_key
    WHEN 'ccos' THEN price_per_token := 9.0;
    WHEN 'str' THEN price_per_token := 0.00911;
    WHEN 'arss' THEN price_per_token := 0.00911;
    ELSE
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Invalid token type: ' || token_type_param,
        'package_checked', package_type_param
      );
  END CASE;

  voucher_apy := CASE token_key
    WHEN 'str' THEN 13.0
    WHEN 'ccos' THEN 13.0
    WHEN 'arss' THEN 12.0
    ELSE 0.0
  END;

  CASE package_type_param
    WHEN 'Foundation ($2,500) ≈ 274,401.67 STR' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5,000) ≈ 548,803.34 STR' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10,000) ≈ 1,097,606.69 STR' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25,000) ≈ 2,744,016.72 STR' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50,000) ≈ 5,488,033.44 STR' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100,000) ≈ 10,976,066.89 STR' THEN token_amount := 10976066.89;
    WHEN 'Foundation ($2,500) ≈ 277.78 CCOS' THEN token_amount := 277.78;
    WHEN 'Pioneer ($5,000) ≈ 555.56 CCOS' THEN token_amount := 555.56;
    WHEN 'Innovator''s ($10,000) ≈ 1,111.11 CCOS' THEN token_amount := 1111.11;
    WHEN 'Architect''s ($25,000) ≈ 2,777.78 CCOS' THEN token_amount := 2777.78;
    WHEN 'Network Builder''s ($50,000) ≈ 5,555.56 CCOS' THEN token_amount := 5555.56;
    WHEN 'Quantum Core ($100,000) ≈ 11,111.11 CCOS' THEN token_amount := 11111.11;
    WHEN 'Foundation ($2,500) ≈ 274,401.67 ARSS' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5,000) ≈ 548,803.34 ARSS' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10,000) ≈ 1,097,606.69 ARSS' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25,000) ≈ 2,744,016.72 ARSS' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50,000) ≈ 5,488,033.44 ARSS' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100,000) ≈ 10,976,066.89 ARSS' THEN token_amount := 10976066.89;
    ELSE
      usd_amount := NULLIF(
        regexp_replace(
          regexp_replace(package_type_param, '^.*\$([0-9,]+).*$' , '\1'),
          ',', '', 'g'
        ),
        ''
      )::numeric;

      IF usd_amount IS NULL THEN
        RETURN jsonb_build_object(
          'success', false,
          'error', 'Could not parse USD amount from package type: ' || package_type_param,
          'package_checked', package_type_param
        );
      END IF;

      token_amount := ROUND((usd_amount / price_per_token)::numeric, 2);
  END CASE;

  PERFORM initialize_user_staking_pools(user_id_param);

  SELECT id
  INTO target_pool_id
  FROM user_staking_pools
  WHERE user_id = user_id_param
    AND pool_type = token_key
    AND stake_duration_months = 3
  ORDER BY created_at ASC
  LIMIT 1;

  IF target_pool_id IS NULL THEN
    INSERT INTO user_staking_pools (
      user_id, pool_type, balance, staked_amount, rewards_earned, apy_rate,
      stake_duration_months, lock_end_date, status, admin_notes, created_at, updated_at
    ) VALUES (
      user_id_param, token_key, 0, 0, 0, voucher_apy, 3,
      NOW() + INTERVAL '3 months', 'active', 'voucher_pool', NOW(), NOW()
    )
    RETURNING id INTO target_pool_id;
  END IF;

  SELECT COALESCE(staked_amount, 0), COALESCE(balance, 0)
  INTO current_staked, current_balance
  FROM user_staking_pools
  WHERE id = target_pool_id;

  new_lock_end := NOW() + INTERVAL '3 months';

  UPDATE user_staking_pools
  SET
    staked_amount = current_staked + token_amount,
    balance = current_balance + token_amount,
    status = COALESCE(NULLIF(status, ''), 'active'),
    apy_rate = CASE WHEN COALESCE(apy_rate, 0) = 0 THEN voucher_apy ELSE apy_rate END,
    dynamic_apy = CASE WHEN COALESCE(dynamic_apy, 0) = 0 THEN voucher_apy ELSE dynamic_apy END,
    lock_end_date = CASE
      WHEN lock_end_date IS NULL THEN new_lock_end
      WHEN lock_end_date < new_lock_end THEN new_lock_end
      ELSE lock_end_date
    END,
    admin_notes = COALESCE(admin_notes, 'voucher_pool'),
    updated_at = NOW()
  WHERE id = target_pool_id;

  INSERT INTO arss_transactions (
    user_id, amount, currency, transaction_type, source_type, description, status
  ) VALUES (
    user_id_param, token_amount, token_key, 'voucher_redemption', 'voucher_system',
    'Voucher redemption: ' || package_type_param, 'completed'
  );

  RETURN jsonb_build_object(
    'success', true,
    'pool_id', target_pool_id,
    'tokens_credited', token_amount,
    'token_type', token_key,
    'package_type', package_type_param,
    'apy_rate_applied', voucher_apy,
    'new_staked_amount', current_staked + token_amount,
    'new_balance', current_balance + token_amount
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;