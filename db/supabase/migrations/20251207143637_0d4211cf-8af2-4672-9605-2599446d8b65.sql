-- Update the provisioning function with correct BIC and country codes
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
  v_existing_count int;
BEGIN
  -- Process each currency
  FOREACH v_currency IN ARRAY p_currencies
  LOOP
    -- Set BIC and country based on currency
    -- BIC format: 4 bank + 2 country + 2 location = 8 chars, all letters
    CASE v_currency
      WHEN 'EUR' THEN
        v_bic := 'CCOIBGRR';  -- Bulgaria (BG) for EUR
        v_country_code := 'BG';
      WHEN 'CHF' THEN
        v_bic := 'CCOICHZZ';  -- Switzerland (CH) for CHF
        v_country_code := 'CH';
      WHEN 'GBP' THEN
        v_bic := 'CCOIGBRR';  -- Great Britain (GB) for GBP
        v_country_code := 'GB';
      ELSE
        v_errors := array_append(v_errors, 'Unsupported currency: ' || v_currency);
        CONTINUE;
    END CASE;

    -- Check if IBAN already exists for this user/currency
    SELECT COUNT(*) INTO v_existing_count
    FROM iban_accounts
    WHERE user_id = p_user_id AND currency = v_currency;
    
    IF v_existing_count > 0 THEN
      CONTINUE; -- Skip if already exists
    END IF;

    -- Generate IBAN components
    v_check_digits := lpad((floor(random() * 90 + 10)::int)::text, 2, '0');
    v_random_part := lpad((floor(random() * 10000000000000000)::bigint)::text, 16, '0');
    
    -- Create IBAN: 2-letter country + 2 check digits + bank code + account number
    v_iban := v_country_code || v_check_digits || 'CCOI' || v_random_part;

    -- Create IBAN account
    BEGIN
      INSERT INTO iban_accounts (
        user_id, iban, bic, account_holder, account_type, 
        country_code, currency, balance, status, is_data_encrypted
      ) VALUES (
        p_user_id, v_iban, v_bic, COALESCE(p_full_name, 'Account Holder'), 
        'personal', v_country_code, v_currency, 0, 'active', false
      );
      
      v_ibans_created := array_append(v_ibans_created, v_currency);
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'IBAN ' || v_currency || ': ' || SQLERRM);
    END;

    -- Check if fiat wallet already exists
    SELECT COUNT(*) INTO v_existing_count
    FROM fiat_wallets
    WHERE user_id = p_user_id AND currency = v_currency;
    
    IF v_existing_count = 0 THEN
      -- Create fiat wallet
      BEGIN
        INSERT INTO fiat_wallets (user_id, currency, balance, available_balance, held_balance)
        VALUES (p_user_id, v_currency, 0, 0, 0);
        
        v_wallets_created := array_append(v_wallets_created, v_currency);
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'Wallet ' || v_currency || ': ' || SQLERRM);
      END;
    END IF;
  END LOOP;

  -- Check if CCoin card already exists
  SELECT COUNT(*) INTO v_existing_count
  FROM prepaid_cards
  WHERE user_id = p_user_id AND network = 'ccoin';
  
  IF v_existing_count = 0 THEN
    -- Create CCoin card
    BEGIN
      v_card_last4 := lpad((floor(random() * 9000 + 1000)::int)::text, 4, '0');
      v_masked_card := 'CCOIN-XXXX-XXXX-' || v_card_last4;
      
      INSERT INTO prepaid_cards (
        user_id, card_type, currency, balance, status, 
        card_last4, masked_card, network, issuer
      ) VALUES (
        p_user_id, 'virtual', 'EUR', 0, 'active',
        v_card_last4, v_masked_card, 'ccoin', 'CCoin Finance'
      );
      
      v_cards_created := array_append(v_cards_created, 'CCoin');
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'CCoin Card: ' || SQLERRM);
    END;
  END IF;

  -- Check if Visa card already exists
  SELECT COUNT(*) INTO v_existing_count
  FROM prepaid_cards
  WHERE user_id = p_user_id AND network = 'visa';
  
  IF v_existing_count = 0 THEN
    -- Create Visa card
    BEGIN
      v_card_last4 := lpad((floor(random() * 9000 + 1000)::int)::text, 4, '0');
      v_masked_card := '4XXX-XXXX-XXXX-' || v_card_last4;
      
      INSERT INTO prepaid_cards (
        user_id, card_type, currency, balance, status,
        card_last4, masked_card, network, issuer, bin
      ) VALUES (
        p_user_id, 'virtual', 'EUR', 0, 'active',
        v_card_last4, v_masked_card, 'visa', 'CCoin Finance', '4XXXXX'
      );
      
      v_cards_created := array_append(v_cards_created, 'Visa');
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'Visa Card: ' || SQLERRM);
    END;
  END IF;

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