-- Update IBAN creation to support multiple currencies: EUR, CHF, GBP
-- Each currency will have its own IBAN with the appropriate country code

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
  
  -- Create IBAN account
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

-- Update bulk creation to create all three currency accounts
CREATE OR REPLACE FUNCTION admin_bulk_create_banking(
  p_create_ibans boolean DEFAULT true,
  p_create_ccoin_cards boolean DEFAULT true,
  p_create_visa_cards boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_record RECORD;
  created_eur_ibans integer := 0;
  created_chf_ibans integer := 0;
  created_gbp_ibans integer := 0;
  created_ccoin_cards integer := 0;
  created_visa_cards integer := 0;
  skipped_users integer := 0;
  v_result uuid;
BEGIN
  -- Only admins can run this
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  
  -- Process all approved users
  FOR user_record IN
    SELECT 
      user_id,
      full_name,
      str_domain_owned,
      str_wallet_address
    FROM user_profiles
    WHERE status = 'approved'
    ORDER BY created_at
  LOOP
    BEGIN
      -- Create IBANs in all three currencies if requested
      IF p_create_ibans THEN
        -- EUR Account
        v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name, 'EUR');
        IF v_result IS NOT NULL THEN
          created_eur_ibans := created_eur_ibans + 1;
        END IF;
        
        -- CHF Account
        v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name, 'CHF');
        IF v_result IS NOT NULL THEN
          created_chf_ibans := created_chf_ibans + 1;
        END IF;
        
        -- GBP Account
        v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name, 'GBP');
        IF v_result IS NOT NULL THEN
          created_gbp_ibans := created_gbp_ibans + 1;
        END IF;
      END IF;
      
      -- Create CCoin card if requested
      IF p_create_ccoin_cards THEN
        v_result := create_ccoin_card_for_user(
          user_record.user_id,
          user_record.str_domain_owned,
          user_record.str_wallet_address
        );
        IF v_result IS NOT NULL THEN
          created_ccoin_cards := created_ccoin_cards + 1;
        END IF;
      END IF;
      
      -- Create Visa card if requested
      IF p_create_visa_cards THEN
        v_result := create_visa_card_for_user(
          user_record.user_id,
          user_record.str_domain_owned
        );
        IF v_result IS NOT NULL THEN
          created_visa_cards := created_visa_cards + 1;
        END IF;
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      skipped_users := skipped_users + 1;
      RAISE LOG 'Error creating banking for user %: %', user_record.user_id, SQLERRM;
    END;
  END LOOP;
  
  -- Log the bulk operation
  INSERT INTO security_audit_log (
    user_id,
    action,
    resource_type,
    details
  ) VALUES (
    auth.uid(),
    'bulk_banking_created',
    'iban_accounts',
    jsonb_build_object(
      'eur_ibans', created_eur_ibans,
      'chf_ibans', created_chf_ibans,
      'gbp_ibans', created_gbp_ibans,
      'ccoin_cards', created_ccoin_cards,
      'visa_cards', created_visa_cards,
      'skipped_users', skipped_users,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'eur_ibans', created_eur_ibans,
    'chf_ibans', created_chf_ibans,
    'gbp_ibans', created_gbp_ibans,
    'ccoin_cards', created_ccoin_cards,
    'visa_cards', created_visa_cards,
    'skipped_users', skipped_users,
    'timestamp', now()
  );
END;
$$;