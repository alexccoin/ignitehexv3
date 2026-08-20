-- Fix voucher crediting so it updates pool principal value correctly and avoids double-crediting

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
BEGIN
  -- Token pricing constants
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

  -- Voucher APY defaults (only used when pool APY is missing/0)
  voucher_apy := CASE token_key
    WHEN 'str' THEN 13.0
    WHEN 'ccos' THEN 13.0
    WHEN 'arss' THEN 12.0
    ELSE 0.0
  END;

  -- Exact matches for old formats (with commas)
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
      -- Parse USD amount from package string and calculate token amount
      usd_amount := NULLIF(
        regexp_replace(
          regexp_replace(package_type_param, '^.*\\$([0-9,]+).*$' , '\\1'),
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

  -- Ensure baseline pools exist (creates 3-month row if missing)
  PERFORM initialize_user_staking_pools(user_id_param);

  -- Pick ONE target 3-month pool row (avoid accidentally updating multiple rows)
  SELECT id
  INTO target_pool_id
  FROM user_staking_pools
  WHERE user_id = user_id_param
    AND pool_type = token_key
    AND stake_duration_months = 3
  ORDER BY created_at ASC
  LIMIT 1;

  -- If somehow missing, create an active 3-month pool row
  IF target_pool_id IS NULL THEN
    INSERT INTO user_staking_pools (
      user_id,
      pool_type,
      balance,
      staked_amount,
      rewards_earned,
      apy_rate,
      stake_duration_months,
      lock_end_date,
      status,
      admin_notes,
      created_at,
      updated_at
    ) VALUES (
      user_id_param,
      token_key,
      0,
      0,
      0,
      voucher_apy,
      3,
      NOW() + INTERVAL '3 months',
      'active',
      'voucher_pool',
      NOW(),
      NOW()
    )
    RETURNING id INTO target_pool_id;
  END IF;

  -- Read current values
  SELECT COALESCE(staked_amount, 0), COALESCE(balance, 0)
  INTO current_staked, current_balance
  FROM user_staking_pools
  WHERE id = target_pool_id;

  new_lock_end := NOW() + INTERVAL '3 months';

  -- IMPORTANT: Voucher credits must affect ONLY the 3-month pool; balance must include principal
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

  -- Log the voucher redemption
  INSERT INTO arss_transactions (
    user_id,
    amount,
    currency,
    transaction_type,
    source_type,
    description,
    status
  ) VALUES (
    user_id_param,
    token_amount,
    token_key,
    'voucher_redemption',
    'voucher_system',
    'Voucher redemption: ' || package_type_param,
    'completed'
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


-- Prevent double-crediting: process_voucher_redemption_with_audit should rely on the existing trigger
-- (auto_credit_voucher_trigger) and simply return the post-trigger state.

CREATE OR REPLACE FUNCTION public.process_voucher_redemption_with_audit(
  voucher_id uuid,
  new_status text,
  performed_by_user_id uuid,
  admin_notes_param text DEFAULT NULL::text,
  client_ip inet DEFAULT NULL::inet,
  user_agent_param text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  voucher_before voucher_redemptions%ROWTYPE;
  voucher_after voucher_redemptions%ROWTYPE;
  final_result jsonb;
  credit_state jsonb;
BEGIN
  -- Get voucher details (before)
  SELECT * INTO voucher_before
  FROM voucher_redemptions
  WHERE id = voucher_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Voucher not found'
    );
  END IF;

  -- Log the status change
  INSERT INTO voucher_redemption_history (
    voucher_redemption_id,
    status_from,
    status_to,
    action_performed,
    performed_by,
    admin_notes,
    ip_address,
    user_agent
  ) VALUES (
    voucher_id,
    voucher_before.status,
    new_status,
    'status_change_' || new_status,
    performed_by_user_id,
    admin_notes_param,
    client_ip,
    user_agent_param
  );

  -- Update voucher status (this will trigger auto_credit_voucher_trigger when moving to approved)
  UPDATE voucher_redemptions
  SET
    status = new_status,
    processed_by = performed_by_user_id,
    processed_at = now(),
    admin_notes = admin_notes_param,
    updated_at = now()
  WHERE id = voucher_id;

  -- Reload voucher details (after trigger effects)
  SELECT * INTO voucher_after
  FROM voucher_redemptions
  WHERE id = voucher_id;

  credit_state := jsonb_build_object(
    'tokens_credited', COALESCE(voucher_after.tokens_credited, false),
    'credited_amount', COALESCE(voucher_after.credited_amount, 0),
    'credited_at', voucher_after.credited_at
  );

  final_result := jsonb_build_object(
    'success', true,
    'voucher_status', voucher_after.status,
    'tokens_credited', COALESCE(voucher_after.tokens_credited, false),
    'credited_amount', COALESCE(voucher_after.credited_amount, 0),
    'credited_at', voucher_after.credited_at,
    'credit_details', credit_state
  );

  -- Log security audit
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    resource_id,
    details,
    ip_address
  ) VALUES (
    performed_by_user_id,
    'voucher_' || new_status,
    'voucher_redemptions',
    voucher_id::text,
    jsonb_build_object(
      'voucher_id', voucher_id,
      'target_user', voucher_after.user_id,
      'package_type', voucher_after.package_type,
      'token_type', voucher_after.token_type,
      'admin_notes', admin_notes_param,
      'credit_state', credit_state
    ),
    client_ip
  );

  RETURN final_result;

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;


-- Backfill: ensure pools with principal have balance + active status so users don't see "missing value"

UPDATE public.user_staking_pools
SET
  balance = GREATEST(COALESCE(balance, 0), COALESCE(staked_amount, 0)),
  status = COALESCE(NULLIF(status, ''), 'active'),
  updated_at = NOW()
WHERE COALESCE(staked_amount, 0) > 0
  AND (
    balance IS NULL OR balance < staked_amount OR status IS NULL OR status = ''
  );

-- Backfill: set lock_end_date for 3-month pools with stake but missing lock_end_date
UPDATE public.user_staking_pools
SET
  lock_end_date = created_at + INTERVAL '3 months',
  updated_at = NOW()
WHERE COALESCE(staked_amount, 0) > 0
  AND stake_duration_months = 3
  AND lock_end_date IS NULL;

-- Backfill: set a reasonable APY for 3-month voucher-like pools that had APY=0
UPDATE public.user_staking_pools
SET
  apy_rate = CASE WHEN pool_type = 'arss' THEN 12.0 ELSE 13.0 END,
  dynamic_apy = CASE
    WHEN dynamic_apy IS NULL OR dynamic_apy = 0 THEN CASE WHEN pool_type = 'arss' THEN 12.0 ELSE 13.0 END
    ELSE dynamic_apy
  END,
  updated_at = NOW()
WHERE COALESCE(staked_amount, 0) > 0
  AND stake_duration_months = 3
  AND pool_type IN ('str', 'ccos', 'arss')
  AND COALESCE(apy_rate, 0) = 0;
