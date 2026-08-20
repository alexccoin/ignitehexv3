-- Update function to handle both old and new package naming conventions
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
  result jsonb;
BEGIN
  -- Map package types to STR token amounts (both old and new naming conventions)
  CASE package_type_param
    -- New naming convention
    WHEN 'Foundation ($2,500) ≈ 274,401.67 STR' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5,000) ≈ 548,803.34 STR' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10,000) ≈ 1,097,606.69 STR' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25,000) ≈ 2,744,016.72 STR' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50,000) ≈ 5,488,033.44 STR' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100,000) ≈ 10,976,066.89 STR' THEN token_amount := 10976066.89;
    
    -- Old naming convention for STR
    WHEN 'STR-BASIC-2500' THEN token_amount := 274401.67; -- Foundation
    WHEN 'STR-PREMIUM-5000' THEN token_amount := 548803.34; -- Pioneer
    WHEN 'STR-ELITE-10000' THEN token_amount := 1097606.69; -- Innovator's
    WHEN 'STR-ENTERPRISE-25000' THEN token_amount := 2744016.72; -- Architect's
    
    -- Old naming convention for CCOS (same amounts as STR for now)
    WHEN 'CCOS-STARTER-2500' THEN token_amount := 274401.67; -- Foundation
    WHEN 'CCOS-PROFESSIONAL-5000' THEN token_amount := 548803.34; -- Pioneer
    WHEN 'CCOS-BUSINESS-10000' THEN token_amount := 1097606.69; -- Innovator's
    WHEN 'CCOS-CORPORATE-25000' THEN token_amount := 2744016.72; -- Architect's
    
    -- Old naming convention for ARSS (same amounts as STR for now)
    WHEN 'ARSS-AI-2500' THEN token_amount := 274401.67; -- Foundation
    WHEN 'ARSS-PRO-5000' THEN token_amount := 548803.34; -- Pioneer
    WHEN 'ARSS-ADVANCED-10000' THEN token_amount := 1097606.69; -- Innovator's
    WHEN 'ARSS-SUPREME-25000' THEN token_amount := 2744016.72; -- Architect's
    
    ELSE 
      RETURN jsonb_build_object(
        'success', false,
        'error', 'Invalid package type: ' || package_type_param
      );
  END CASE;

  -- Initialize user staking pools if they don't exist
  PERFORM initialize_user_staking_pools(user_id_param);

  -- Get current balance
  DECLARE
    current_balance numeric;
  BEGIN
    SELECT balance INTO current_balance
    FROM user_staking_pools
    WHERE user_id = user_id_param AND pool_type = token_type_param;
    
    IF current_balance IS NULL THEN
      current_balance := 0;
    END IF;
  END;

  -- Update the pool balance
  UPDATE user_staking_pools
  SET 
    balance = balance + token_amount,
    updated_at = now()
  WHERE user_id = user_id_param AND pool_type = token_type_param;

  -- Log the transaction
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
    'Voucher redemption: ' || package_type_param,
    'completed'
  );

  -- Return success result
  RETURN jsonb_build_object(
    'success', true,
    'tokens_credited', token_amount,
    'token_type', token_type_param,
    'package_type', package_type_param,
    'new_balance', current_balance + token_amount
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;