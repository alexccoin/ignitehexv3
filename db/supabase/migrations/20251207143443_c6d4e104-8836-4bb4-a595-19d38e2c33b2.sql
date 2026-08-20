-- Drop duplicate functions that conflict
DROP FUNCTION IF EXISTS public.create_iban_for_user(uuid, text, text);

-- Create a clean, simple function for bulk IBAN creation
CREATE OR REPLACE FUNCTION public.provision_banking_for_user(
  p_user_id uuid,
  p_full_name text,
  p_currencies text[] DEFAULT ARRAY['EUR', 'CHF', 'GBP']
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_currency text;
  v_iban text;
  v_bic text;
  v_country_code text;
  v_check_digits text;
  v_random_part text;
  v_ibans_created text[] := '{}';
  v_wallets_created text[] := '{}';
  v_cards_created text[] := '{}';
  v_errors text[] := '{}';
  v_card_last4 text;
  v_masked_card text;
BEGIN
  -- Process each currency
  FOREACH v_currency IN ARRAY p_currencies
  LOOP
    -- Set BIC and country based on currency (BIC must be 8 or 11 chars: 6 letters + 2 alphanum + optional 3)
    CASE v_currency
      WHEN 'EUR' THEN
        v_bic := 'CCOIEUXX';  -- 8 chars: CCOI + EU + XX
        v_country_code := 'EU';
      WHEN 'CHF' THEN
        v_bic := 'CCOICHZZ';  -- 8 chars: CCOI + CH + ZZ
        v_country_code := 'CH';
      WHEN 'GBP' THEN
        v_bic := 'CCOIGBXX';  -- 8 chars: CCOI + GB + XX
        v_country_code := 'GB';
      ELSE
        v_errors := array_append(v_errors, 'Unsupported currency: ' || v_currency);
        CONTINUE;
    END CASE;

    -- Generate IBAN components
    v_check_digits := lpad((floor(random() * 90 + 10)::int)::text, 2, '0');
    v_random_part := lpad((floor(random() * 10000000000000000)::bigint)::text, 16, '0');
    
    -- Create IBAN: 2-letter country + 2 check digits + up to 30 alphanumerics
    v_iban := v_country_code || v_check_digits || 'CCOI' || v_random_part;

    -- Create IBAN account if not exists
    BEGIN
      INSERT INTO iban_accounts (
        user_id, iban, bic, account_holder, account_type, 
        country_code, currency, balance, status, is_data_encrypted
      ) VALUES (
        p_user_id, v_iban, v_bic, COALESCE(p_full_name, 'Account Holder'), 
        'personal', v_country_code, v_currency, 0, 'active', false
      )
      ON CONFLICT DO NOTHING;
      
      IF FOUND THEN
        v_ibans_created := array_append(v_ibans_created, v_currency);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'IBAN ' || v_currency || ': ' || SQLERRM);
    END;

    -- Create fiat wallet if not exists
    BEGIN
      INSERT INTO fiat_wallets (user_id, currency, balance, available_balance, held_balance)
      VALUES (p_user_id, v_currency, 0, 0, 0)
      ON CONFLICT DO NOTHING;
      
      IF FOUND THEN
        v_wallets_created := array_append(v_wallets_created, v_currency);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'Wallet ' || v_currency || ': ' || SQLERRM);
    END;
  END LOOP;

  -- Create CCoin card if not exists
  BEGIN
    v_card_last4 := lpad((floor(random() * 9000 + 1000)::int)::text, 4, '0');
    v_masked_card := 'CCOIN-XXXX-XXXX-' || v_card_last4;
    
    INSERT INTO prepaid_cards (
      user_id, card_type, currency, balance, status, 
      card_last4, masked_card, network, issuer
    ) VALUES (
      p_user_id, 'virtual', 'EUR', 0, 'active',
      v_card_last4, v_masked_card, 'ccoin', 'CCoin Finance'
    )
    ON CONFLICT DO NOTHING;
    
    IF FOUND THEN
      v_cards_created := array_append(v_cards_created, 'CCoin');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_errors := array_append(v_errors, 'CCoin Card: ' || SQLERRM);
  END;

  -- Create Visa card if not exists
  BEGIN
    v_card_last4 := lpad((floor(random() * 9000 + 1000)::int)::text, 4, '0');
    v_masked_card := '4XXX-XXXX-XXXX-' || v_card_last4;
    
    INSERT INTO prepaid_cards (
      user_id, card_type, currency, balance, status,
      card_last4, masked_card, network, issuer, bin
    ) VALUES (
      p_user_id, 'virtual', 'EUR', 0, 'active',
      v_card_last4, v_masked_card, 'visa', 'CCoin Finance', '4XXXXX'
    )
    ON CONFLICT DO NOTHING;
    
    IF FOUND THEN
      v_cards_created := array_append(v_cards_created, 'Visa');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_errors := array_append(v_errors, 'Visa Card: ' || SQLERRM);
  END;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'ibans_created', v_ibans_created,
    'wallets_created', v_wallets_created,
    'cards_created', v_cards_created,
    'errors', v_errors
  );
END;
$$;

-- Create function to bulk provision all approved CCoin Bank members
CREATE OR REPLACE FUNCTION public.bulk_provision_ccoin_banking(
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_app RECORD;
  v_result jsonb;
  v_all_results jsonb[] := '{}';
  v_total_ibans int := 0;
  v_total_wallets int := 0;
  v_total_cards int := 0;
  v_processed int := 0;
  v_errors text[] := '{}';
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Loop through approved CCoin Bank applications
  FOR v_app IN 
    SELECT cba.user_id, cba.full_name
    FROM ccoin_bank_applications cba
    WHERE cba.status = 'approved'
    ORDER BY cba.created_at
    LIMIT p_limit
    OFFSET p_offset
  LOOP
    -- Provision banking for this user
    v_result := provision_banking_for_user(v_app.user_id, v_app.full_name);
    
    -- Accumulate counts
    v_total_ibans := v_total_ibans + jsonb_array_length(COALESCE(v_result->'ibans_created', '[]'::jsonb));
    v_total_wallets := v_total_wallets + jsonb_array_length(COALESCE(v_result->'wallets_created', '[]'::jsonb));
    v_total_cards := v_total_cards + jsonb_array_length(COALESCE(v_result->'cards_created', '[]'::jsonb));
    v_processed := v_processed + 1;
    
    -- Track any errors
    IF jsonb_array_length(COALESCE(v_result->'errors', '[]'::jsonb)) > 0 THEN
      v_all_results := array_append(v_all_results, v_result);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'processed', v_processed,
    'ibans_created', v_total_ibans,
    'wallets_created', v_total_wallets,
    'cards_created', v_total_cards,
    'offset', p_offset,
    'limit', p_limit,
    'has_more', v_processed = p_limit,
    'results_with_errors', v_all_results
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.provision_banking_for_user(uuid, text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_provision_ccoin_banking(int, int) TO authenticated;