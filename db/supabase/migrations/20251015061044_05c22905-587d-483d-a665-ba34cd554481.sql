-- Create IBAN per currency (not just one per user)
CREATE OR REPLACE FUNCTION public.create_iban_for_user(p_user_id uuid, p_currency text, p_country text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iban_id uuid;
  v_masked_iban text;
  v_masked_bic text;
  v_existing uuid;
  v_seed text;
  v_currency_upper text;
BEGIN
  v_currency_upper := upper(coalesce(p_currency, 'EUR'));
  
  -- Check for existing IBAN for this user AND currency
  SELECT ia.id INTO v_existing
  FROM public.iban_accounts ia
  WHERE ia.user_id = p_user_id
    AND upper(coalesce(ia.currency, 'EUR')) = v_currency_upper
  ORDER BY ia.created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Generate masked IBAN and BIC
  v_seed := encode(extensions.digest(now()::text || random()::text || v_currency_upper || p_user_id::text, 'sha256'), 'hex');

  v_masked_iban := v_currency_upper || substr(v_seed, 1, 18);
  IF length(v_masked_iban) > 8 THEN
    v_masked_iban := left(v_masked_iban, 4) || repeat('*', greatest(length(v_masked_iban) - 8, 0)) || right(v_masked_iban, 4);
  ELSE
    v_masked_iban := repeat('*', length(v_masked_iban));
  END IF;

  v_masked_bic := 'BIC' || substr(v_seed, 5, 8);
  IF length(v_masked_bic) > 6 THEN
    v_masked_bic := left(v_masked_bic, 3) || repeat('*', greatest(length(v_masked_bic) - 6, 0)) || right(v_masked_bic, 3);
  ELSE
    v_masked_bic := repeat('*', length(v_masked_bic));
  END IF;

  INSERT INTO public.iban_accounts (user_id, iban, bic, currency, is_data_encrypted)
  VALUES (p_user_id, v_masked_iban, v_masked_bic, v_currency_upper, true)
  RETURNING id INTO v_iban_id;

  RETURN v_iban_id;
END;
$$;

-- CCoin card starting with "str."
CREATE OR REPLACE FUNCTION public.create_ccoin_card_for_user(p_user_id uuid, p_str_domain text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card_id uuid;
  v_last4 text;
  v_masked text;
  v_existing uuid;
  v_domain_clean text;
BEGIN
  -- Check if CCoin card exists
  SELECT id INTO v_existing
  FROM public.prepaid_cards
  WHERE user_id = p_user_id AND network = 'ccoin'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Clean domain (remove .str if present)
  v_domain_clean := regexp_replace(coalesce(p_str_domain, 'unknown'), '\.str$', '', 'i');
  
  v_last4 := lpad((1000 + floor(random() * 9000))::int::text, 4, '0');
  -- CCoin card starts with "str."
  v_masked := 'str.' || v_domain_clean || '******' || v_last4;

  INSERT INTO public.prepaid_cards (
    user_id, balance, card_type, currency, status, network, issuer,
    bin, card_last4, masked_card, domain_part
  ) VALUES (
    p_user_id, 0, 'virtual', 'CCOIN', 'active', 'ccoin', 'CCoin Network',
    'str', v_last4, v_masked, p_str_domain
  )
  RETURNING id INTO v_card_id;

  RETURN v_card_id;
END;
$$;

-- Virtual Visa card (proper implementation)
CREATE OR REPLACE FUNCTION public.create_visa_card_for_user(p_user_id uuid, p_str_domain text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card_id uuid;
  v_last4 text;
  v_masked text;
  v_existing uuid;
BEGIN
  -- Check if Visa card exists
  SELECT id INTO v_existing
  FROM public.prepaid_cards
  WHERE user_id = p_user_id AND network = 'visa'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_last4 := lpad((1000 + floor(random() * 9000))::int::text, 4, '0');
  -- Visa cards start with 4
  v_masked := '4xxxxxx******' || v_last4;

  INSERT INTO public.prepaid_cards (
    user_id, balance, card_type, currency, status, network, issuer,
    bin, card_last4, masked_card, domain_part
  ) VALUES (
    p_user_id, 0, 'virtual', 'EUR', 'active', 'visa', 'CCoin Finance',
    '4xxxxxx', v_last4, v_masked, p_str_domain
  )
  RETURNING id INTO v_card_id;

  RETURN v_card_id;
END;
$$;