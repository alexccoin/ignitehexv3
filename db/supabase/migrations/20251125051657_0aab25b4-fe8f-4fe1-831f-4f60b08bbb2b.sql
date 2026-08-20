-- Fix voucher crediting to use correct token type from package name instead of token_type column
CREATE OR REPLACE FUNCTION credit_voucher_tokens(
  user_id_param uuid,
  token_type_param text,
  package_type_param text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  token_amount numeric;
  correct_token_type text;
  result jsonb;
  current_balance numeric;
BEGIN
  -- CRITICAL FIX: Extract correct token type from package name instead of using token_type_param
  -- This fixes the bug where CCOS was credited when package says STR
  IF package_type_param ILIKE '%STR%' AND package_type_param NOT ILIKE '%ARSS%' THEN
    correct_token_type := 'str';
  ELSIF package_type_param ILIKE '%CCOS%' THEN
    correct_token_type := 'ccos';
  ELSIF package_type_param ILIKE '%ARSS%' THEN
    correct_token_type := 'arss';
  ELSE
    -- Fallback to token_type_param if we can't determine from package name
    correct_token_type := LOWER(token_type_param);
  END IF;

  -- Map package types to token amounts with comma support
  -- Remove commas from package names for consistent matching
  CASE REPLACE(package_type_param, ',', '')
    -- New naming convention for STR (without commas)
    WHEN 'Foundation ($2500) ≈ 274401.67 STR' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5000) ≈ 548803.34 STR' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10000) ≈ 1097606.69 STR' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25000) ≈ 2744016.72 STR' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50000) ≈ 5488033.44 STR' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100000) ≈ 10976066.89 STR' THEN token_amount := 10976066.89;
    
    -- CCOS Packages ($9 per token)
    WHEN 'Foundation ($2500) ≈ 277.78 CCOS' THEN token_amount := 277.78;
    WHEN 'Pioneer ($5000) ≈ 555.56 CCOS' THEN token_amount := 555.56;
    WHEN 'Innovator''s ($10000) ≈ 1111.11 CCOS' THEN token_amount := 1111.11;
    WHEN 'Architect''s ($25000) ≈ 2777.78 CCOS' THEN token_amount := 2777.78;
    WHEN 'Network Builder''s ($50000) ≈ 5555.56 CCOS' THEN token_amount := 5555.56;
    WHEN 'Quantum Core ($100000) ≈ 11111.11 CCOS' THEN token_amount := 11111.11;
    
    -- ARSS Packages
    WHEN 'Foundation ($2500) ≈ 274401.67 ARSS' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5000) ≈ 548803.34 ARSS' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10000) ≈ 1097606.69 ARSS' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25000) ≈ 2744016.72 ARSS' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50000) ≈ 5488033.44 ARSS' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100000) ≈ 10976066.89 ARSS' THEN token_amount := 10976066.89;
    
    -- Old naming convention for STR
    WHEN 'STR-BASIC-2500' THEN token_amount := 274401.67;
    WHEN 'STR-PREMIUM-5000' THEN token_amount := 548803.34;
    WHEN 'STR-ELITE-10000' THEN token_amount := 1097606.69;
    WHEN 'STR-ENTERPRISE-25000' THEN token_amount := 2744016.72;
    
    -- Old naming convention for CCOS
    WHEN 'CCOS-STARTER-2500' THEN token_amount := 277.78;
    WHEN 'CCOS-PROFESSIONAL-5000' THEN token_amount := 555.56;
    WHEN 'CCOS-BUSINESS-10000' THEN token_amount := 1111.11;
    WHEN 'CCOS-CORPORATE-25000' THEN token_amount := 2777.78;
    
    -- Old naming convention for ARSS
    WHEN 'ARSS-AI-2500' THEN token_amount := 274401.67;
    WHEN 'ARSS-PRO-5000' THEN token_amount := 548803.34;
    WHEN 'ARSS-ADVANCED-10000' THEN token_amount := 1097606.69;
    WHEN 'ARSS-SUPREME-25000' THEN token_amount := 2744016.72;
    
    ELSE 
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Invalid package type: ' || package_type_param,
        'package_checked', REPLACE(package_type_param, ',', '')
      );
  END CASE;

  -- Initialize user staking pools if they don't exist
  PERFORM initialize_user_staking_pools(user_id_param);

  -- Get current balance for the CORRECT token type
  SELECT balance INTO current_balance
  FROM user_staking_pools
  WHERE user_id = user_id_param 
    AND pool_type = correct_token_type
    AND stake_duration_months = 3;
  
  IF current_balance IS NULL THEN
    current_balance := 0;
  END IF;

  -- Update the pool balance with the CORRECT token type
  UPDATE user_staking_pools
  SET 
    balance = balance + token_amount,
    staked_amount = staked_amount + token_amount,
    updated_at = now()
  WHERE user_id = user_id_param 
    AND pool_type = correct_token_type
    AND stake_duration_months = 3;

  -- Log the transaction with corrected token type
  INSERT INTO arss_transactions (
    user_id,
    amount,
    transaction_type,
    source_type,
    description,
    status
  ) VALUES (
    user_id_param,
    token_amount,
    'voucher_redemption',
    'voucher_system',
    UPPER(correct_token_type) || ' voucher redemption: ' || package_type_param,
    'completed'
  );

  -- Return success result with corrected token type
  RETURN jsonb_build_object(
    'success', true,
    'tokens_credited', token_amount,
    'token_type', correct_token_type,
    'original_token_type_param', token_type_param,
    'package_type', package_type_param,
    'new_balance', current_balance + token_amount
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'token_type_used', correct_token_type,
    'package_type', package_type_param
  );
END;
$function$;