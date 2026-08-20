-- Create or update function to handle voucher token distribution with new package amounts
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
  -- Map package types to STR token amounts
  CASE package_type_param
    WHEN 'Foundation ($2,500) ≈ 274,401.67 STR' THEN token_amount := 274401.67;
    WHEN 'Pioneer ($5,000) ≈ 548,803.34 STR' THEN token_amount := 548803.34;
    WHEN 'Innovator''s ($10,000) ≈ 1,097,606.69 STR' THEN token_amount := 1097606.69;
    WHEN 'Architect''s ($25,000) ≈ 2,744,016.72 STR' THEN token_amount := 2744016.72;
    WHEN 'Network Builder''s ($50,000) ≈ 5,488,033.44 STR' THEN token_amount := 5488033.44;
    WHEN 'Quantum Core ($100,000) ≈ 10,976,066.89 STR' THEN token_amount := 10976066.89;
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

-- Create or update function to process voucher redemption with audit trail
CREATE OR REPLACE FUNCTION process_voucher_redemption_with_audit(
  voucher_id uuid,
  new_status text,
  performed_by_user_id uuid,
  admin_notes_param text DEFAULT NULL,
  client_ip inet DEFAULT NULL,
  user_agent_param text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  voucher_record voucher_redemptions%ROWTYPE;
  credit_result jsonb;
  final_result jsonb;
BEGIN
  -- Get voucher details
  SELECT * INTO voucher_record
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
    voucher_record.status,
    new_status,
    'status_change_' || new_status,
    performed_by_user_id,
    admin_notes_param,
    client_ip,
    user_agent_param
  );

  -- Update voucher status
  UPDATE voucher_redemptions
  SET 
    status = new_status,
    processed_by = performed_by_user_id,
    processed_at = now(),
    admin_notes = admin_notes_param,
    updated_at = now()
  WHERE id = voucher_id;

  -- If approved, credit the tokens
  IF new_status = 'approved' THEN
    -- Credit tokens using the new function
    SELECT credit_voucher_tokens(
      voucher_record.user_id,
      voucher_record.token_type,
      voucher_record.package_type
    ) INTO credit_result;
    
    -- Update voucher with credit information
    UPDATE voucher_redemptions
    SET 
      tokens_credited = (credit_result->>'success')::boolean,
      credited_amount = CASE 
        WHEN (credit_result->>'success')::boolean THEN (credit_result->>'tokens_credited')::numeric
        ELSE 0
      END,
      credited_at = CASE 
        WHEN (credit_result->>'success')::boolean THEN now()
        ELSE NULL
      END,
      updated_at = now()
    WHERE id = voucher_id;
    
    final_result := jsonb_build_object(
      'success', true,
      'voucher_status', new_status,
      'tokens_credited', credit_result->>'success',
      'credit_details', credit_result
    );
  ELSE
    final_result := jsonb_build_object(
      'success', true,
      'voucher_status', new_status,
      'tokens_credited', false
    );
  END IF;

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
      'target_user', voucher_record.user_id,
      'package_type', voucher_record.package_type,
      'token_type', voucher_record.token_type,
      'admin_notes', admin_notes_param,
      'credit_result', credit_result
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