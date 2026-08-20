-- Fix voucher crediting to prevent overallocation across multiple pool durations

CREATE OR REPLACE FUNCTION public.credit_voucher_tokens(
  user_id_param uuid,
  token_type_param text,
  package_type_param text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  token_amount numeric;
  usd_amount numeric;
  price_per_token numeric;
  current_staked numeric := 0;
  token_key text := lower(token_type_param);
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

  -- Ensure baseline pools exist
  PERFORM initialize_user_staking_pools(user_id_param);

  -- Read current stake (3-month pool only)
  SELECT staked_amount INTO current_staked
  FROM user_staking_pools
  WHERE user_id = user_id_param
    AND pool_type = token_key
    AND stake_duration_months = 3;

  current_staked := COALESCE(current_staked, 0);

  -- IMPORTANT: Voucher credits must ONLY affect the 3-month pool, and must be locked principal
  UPDATE user_staking_pools
  SET
    staked_amount = COALESCE(staked_amount, 0) + token_amount,
    updated_at = now()
  WHERE user_id = user_id_param
    AND pool_type = token_key
    AND stake_duration_months = 3;

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
    'tokens_credited', token_amount,
    'token_type', token_key,
    'package_type', package_type_param,
    'new_staked_amount', current_staked + token_amount
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;


-- Backward-compatible wrapper: older code paths calling the 4-arg version must not overallocation-credit every duration.
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
  res jsonb;
  credited numeric := 0;
BEGIN
  SELECT public.credit_voucher_tokens(user_id_param, token_type_param, package_type_param)
    INTO res;

  IF COALESCE((res->>'success')::boolean, false) THEN
    credited := COALESCE((res->>'tokens_credited')::numeric, 0);

    UPDATE voucher_redemptions
    SET
      tokens_credited = true,
      credited_amount = credited,
      credited_at = now(),
      updated_at = now()
    WHERE id = voucher_id;

    RETURN credited;
  END IF;

  UPDATE voucher_redemptions
  SET
    tokens_credited = false,
    credited_amount = 0,
    updated_at = now()
  WHERE id = voucher_id;

  RETURN 0;

EXCEPTION WHEN OTHERS THEN
  RETURN 0;
END;
$function$;
