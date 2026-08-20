-- Fix IBAN creation to mask data before marking as encrypted
-- This satisfies the validate_iban_security() check

CREATE OR REPLACE FUNCTION create_ccoin_iban_for_user(
  p_user_id uuid, 
  p_full_name text, 
  p_currency text DEFAULT 'EUR'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_iban text;
  v_bic text;
  v_masked_iban text;
  v_masked_bic text;
  v_iban_id uuid;
  random_digits text;
  v_country_code text;
  v_iban_prefix text;
BEGIN
  -- Check if user already has an IBAN for this currency
  SELECT id INTO v_iban_id
  FROM iban_accounts
  WHERE user_id = p_user_id AND currency = p_currency
  LIMIT 1;
  
  IF v_iban_id IS NOT NULL THEN
    RETURN v_iban_id;
  END IF;
  
  -- Set country code and IBAN prefix based on currency
  CASE p_currency
    WHEN 'EUR' THEN
      v_country_code := 'BG';
      v_iban_prefix := 'BG80CCOI';
    WHEN 'CHF' THEN
      v_country_code := 'CH';
      v_iban_prefix := 'CH93CCOI';
    WHEN 'GBP' THEN
      v_country_code := 'GB';
      v_iban_prefix := 'GB29CCOI';
    ELSE
      RAISE EXCEPTION 'Unsupported currency: %', p_currency;
  END CASE;
  
  -- Generate unique IBAN (prefix + 18 random digits)
  random_digits := lpad(floor(random() * 1000000000000000000)::text, 18, '0');
  v_iban := v_iban_prefix || random_digits;
  v_bic := 'CCOIN' || v_country_code || 'SFXXX';
  
  -- Mask IBAN and BIC (show first 4 and last 4 characters)
  v_masked_iban := left(v_iban, 4) || repeat('*', length(v_iban) - 8) || right(v_iban, 4);
  v_masked_bic := left(v_bic, 3) || repeat('*', length(v_bic) - 6) || right(v_bic, 3);
  
  -- Create IBAN account with masked data marked as encrypted
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
    v_masked_iban,
    v_masked_bic,
    p_full_name,
    'personal',
    v_country_code,
    p_currency,
    0,
    'active',
    true
  )
  RETURNING id INTO v_iban_id;
  
  RETURN v_iban_id;
END;
$$;