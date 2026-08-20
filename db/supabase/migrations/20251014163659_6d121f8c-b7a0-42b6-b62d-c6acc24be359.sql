-- Fix IBAN and card creation functions to work with encryption triggers
-- The issue is that we're setting is_data_encrypted = true without providing encrypted fields
-- Solution: Set is_data_encrypted = false and let the auto-encryption triggers handle it

CREATE OR REPLACE FUNCTION create_ccoin_iban_for_user(p_user_id uuid, p_full_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iban text;
  v_bic text;
  v_iban_id uuid;
  random_digits text;
BEGIN
  -- Check if user already has an IBAN
  SELECT id INTO v_iban_id
  FROM iban_accounts
  WHERE user_id = p_user_id
  LIMIT 1;
  
  IF v_iban_id IS NOT NULL THEN
    RETURN v_iban_id;
  END IF;
  
  -- Generate CCoin IBAN (BG80CCOI + 18 random digits)
  random_digits := lpad(floor(random() * 1000000000000000000)::text, 18, '0');
  v_iban := 'BG80CCOI' || random_digits;
  v_bic := 'CCOINBGSFXXX';
  
  -- Create IBAN account - let auto-encryption triggers handle encryption
  INSERT INTO iban_accounts (
    user_id,
    iban,
    bic,
    account_holder,
    account_type,
    country_code,
    currency,
    balance,
    status,
    is_data_encrypted
  ) VALUES (
    p_user_id,
    v_iban,
    v_bic,
    p_full_name,
    'personal',
    'BG',
    'EUR',
    0,
    'active',
    false  -- Changed to false to let triggers handle encryption
  )
  RETURNING id INTO v_iban_id;
  
  RETURN v_iban_id;
END;
$$;

CREATE OR REPLACE FUNCTION create_ccoin_card_for_user(p_user_id uuid, p_str_domain text, p_str_wallet text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card_id uuid;
  v_domain text;
  v_suffix text;
  v_identifier text;
BEGIN
  -- Check if user already has a CCoin card
  SELECT id INTO v_card_id
  FROM prepaid_cards
  WHERE user_id = p_user_id AND network = 'ccoin'
  LIMIT 1;
  
  IF v_card_id IS NOT NULL THEN
    RETURN v_card_id;
  END IF;
  
  -- Prepare domain and wallet suffix
  v_domain := COALESCE(p_str_domain, 'user' || substring(p_user_id::text, 1, 8));
  v_suffix := COALESCE(
    regexp_replace(p_str_wallet, '^strzk13', '', 'i'),
    lpad(floor(random() * 10000000000000)::text, 13, '0')
  );
  v_suffix := right(v_suffix, 13);
  v_identifier := 'ccoin:' || v_domain || ':' || v_suffix;
  
  -- Create CCoin card
  INSERT INTO prepaid_cards (
    user_id,
    balance,
    card_type,
    currency,
    status,
    network,
    card_last4,
    masked_card,
    domain_part,
    wallet_suffix,
    full_identifier
  ) VALUES (
    p_user_id,
    0,
    'virtual',
    'CCOIN',
    'active',
    'ccoin',
    right(v_suffix, 4),
    'ccoin:' || v_domain || ':*********' || right(v_suffix, 4),
    v_domain,
    v_suffix,
    v_identifier
  )
  RETURNING id INTO v_card_id;
  
  RETURN v_card_id;
END;
$$;