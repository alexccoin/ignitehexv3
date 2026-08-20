-- Fix create_complete_banking_products function with correct column names
CREATE OR REPLACE FUNCTION public.create_complete_banking_products(
  p_user_id uuid,
  p_str_domain text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb := '{}'::jsonb;
  v_eur_iban_id uuid;
  v_chf_iban_id uuid;
  v_gbp_iban_id uuid;
  v_visa_virtual_id uuid;
  v_visa_physical_id uuid;
  v_ccoin_virtual_id uuid;
  v_ccoin_physical_id uuid;
  v_domain text;
  v_last4 text;
  v_masked text;
  v_full_identifier text;
BEGIN
  -- Get user's domain if not provided
  IF p_str_domain IS NULL THEN
    SELECT str_domain_owned INTO v_domain FROM user_profiles WHERE user_id = p_user_id;
  ELSE
    v_domain := p_str_domain;
  END IF;

  -- Create EUR IBAN (using country_code instead of country)
  BEGIN
    INSERT INTO iban_accounts (
      user_id, iban, bic, account_type, currency, country_code, 
      is_data_encrypted, status
    ) VALUES (
      p_user_id, '***ENCRYPTED***', '***ENCRYPTED***', 
      'personal', 'EUR', 'DE', true, 'active'
    )
    ON CONFLICT (user_id, currency) DO NOTHING
    RETURNING id INTO v_eur_iban_id;
    v_result := jsonb_set(v_result, '{eur_iban_id}', to_jsonb(v_eur_iban_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{eur_iban_error}', to_jsonb(SQLERRM));
  END;

  -- Create CHF IBAN (using country_code instead of country)
  BEGIN
    INSERT INTO iban_accounts (
      user_id, iban, bic, account_type, currency, country_code, 
      is_data_encrypted, status
    ) VALUES (
      p_user_id, '***ENCRYPTED***', '***ENCRYPTED***', 
      'personal', 'CHF', 'CH', true, 'active'
    )
    ON CONFLICT (user_id, currency) DO NOTHING
    RETURNING id INTO v_chf_iban_id;
    v_result := jsonb_set(v_result, '{chf_iban_id}', to_jsonb(v_chf_iban_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{chf_iban_error}', to_jsonb(SQLERRM));
  END;

  -- Create GBP IBAN (using country_code instead of country)
  BEGIN
    INSERT INTO iban_accounts (
      user_id, iban, bic, account_type, currency, country_code, 
      is_data_encrypted, status
    ) VALUES (
      p_user_id, '***ENCRYPTED***', '***ENCRYPTED***', 
      'personal', 'GBP', 'GB', true, 'active'
    )
    ON CONFLICT (user_id, currency) DO NOTHING
    RETURNING id INTO v_gbp_iban_id;
    v_result := jsonb_set(v_result, '{gbp_iban_id}', to_jsonb(v_gbp_iban_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{gbp_iban_error}', to_jsonb(SQLERRM));
  END;

  -- Create Virtual Visa Card
  BEGIN
    v_last4 := lpad(floor(1000 + random() * 9000)::text, 4, '0');
    v_masked := '4xxxxxx******' || v_last4;
    v_full_identifier := 'VISA-' || COALESCE(v_domain, 'USER') || '-V-' || v_last4;
    
    INSERT INTO prepaid_cards (
      user_id, balance, card_type, currency, status, network, 
      issuer, bin, card_last4, masked_card, domain_part, 
      full_identifier, physical_card
    ) VALUES (
      p_user_id, 0, 'virtual', 'EUR', 'active', 'visa', 
      'CCoin Finance', '4xxxxxx', v_last4, v_masked, v_domain,
      v_full_identifier, false
    )
    ON CONFLICT (user_id, network, card_type) DO NOTHING
    RETURNING id INTO v_visa_virtual_id;
    v_result := jsonb_set(v_result, '{visa_virtual_id}', to_jsonb(v_visa_virtual_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{visa_virtual_error}', to_jsonb(SQLERRM));
  END;

  -- Create Physical Visa Card
  BEGIN
    v_last4 := lpad(floor(1000 + random() * 9000)::text, 4, '0');
    v_masked := '4xxxxxx******' || v_last4;
    v_full_identifier := 'VISA-' || COALESCE(v_domain, 'USER') || '-P-' || v_last4;
    
    INSERT INTO prepaid_cards (
      user_id, balance, card_type, currency, status, network, 
      issuer, bin, card_last4, masked_card, domain_part, 
      full_identifier, physical_card, shipping_status
    ) VALUES (
      p_user_id, 0, 'physical', 'EUR', 'pending', 'visa', 
      'CCoin Finance', '4xxxxxx', v_last4, v_masked, v_domain,
      v_full_identifier, true, 'pending'
    )
    ON CONFLICT (user_id, network, physical_card) WHERE physical_card = true DO NOTHING
    RETURNING id INTO v_visa_physical_id;
    v_result := jsonb_set(v_result, '{visa_physical_id}', to_jsonb(v_visa_physical_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{visa_physical_error}', to_jsonb(SQLERRM));
  END;

  -- Create Virtual CCoin Card
  BEGIN
    SELECT str_wallet_address INTO v_last4 FROM user_profiles WHERE user_id = p_user_id;
    v_last4 := COALESCE(right(v_last4, 13), lpad(floor(random() * 10000000000000)::bigint::text, 13, '0'));
    v_full_identifier := 'CC-' || COALESCE(v_domain, 'USER') || '-V-' || v_last4;
    
    INSERT INTO prepaid_cards (
      user_id, balance, card_type, currency, status, network, 
      issuer, domain_part, full_identifier, card_last4, physical_card
    ) VALUES (
      p_user_id, 0, 'virtual', 'CCOIN', 'active', 'ccoin', 
      'CCoin Network', v_domain, v_full_identifier, v_last4, false
    )
    ON CONFLICT (user_id, network, card_type) DO NOTHING
    RETURNING id INTO v_ccoin_virtual_id;
    v_result := jsonb_set(v_result, '{ccoin_virtual_id}', to_jsonb(v_ccoin_virtual_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{ccoin_virtual_error}', to_jsonb(SQLERRM));
  END;

  -- Create Physical CCoin Card
  BEGIN
    SELECT str_wallet_address INTO v_last4 FROM user_profiles WHERE user_id = p_user_id;
    v_last4 := COALESCE(right(v_last4, 13), lpad(floor(random() * 10000000000000)::bigint::text, 13, '0'));
    v_full_identifier := 'CC-' || COALESCE(v_domain, 'USER') || '-P-' || v_last4;
    
    INSERT INTO prepaid_cards (
      user_id, balance, card_type, currency, status, network, 
      issuer, domain_part, full_identifier, card_last4, physical_card, shipping_status
    ) VALUES (
      p_user_id, 0, 'physical', 'CCOIN', 'pending', 'ccoin', 
      'CCoin Network', v_domain, v_full_identifier, v_last4, true, 'pending'
    )
    ON CONFLICT (user_id, network, physical_card) WHERE physical_card = true DO NOTHING
    RETURNING id INTO v_ccoin_physical_id;
    v_result := jsonb_set(v_result, '{ccoin_physical_id}', to_jsonb(v_ccoin_physical_id));
  EXCEPTION WHEN OTHERS THEN
    v_result := jsonb_set(v_result, '{ccoin_physical_error}', to_jsonb(SQLERRM));
  END;

  v_result := jsonb_set(v_result, '{success}', 'true'::jsonb);
  RETURN v_result;
END;
$$;