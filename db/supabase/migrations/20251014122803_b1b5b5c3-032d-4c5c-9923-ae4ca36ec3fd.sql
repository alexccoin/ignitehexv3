-- Enhanced IBAN and CCoin card auto-creation system
-- This creates IBANs and cards automatically for all new users

-- Function to generate CCoin IBAN for a user
CREATE OR REPLACE FUNCTION public.create_ccoin_iban_for_user(p_user_id uuid, p_full_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
  
  -- Create IBAN account (encrypted by default via trigger)
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
    true
  )
  RETURNING id INTO v_iban_id;
  
  RETURN v_iban_id;
END;
$$;

-- Function to create CCoin network card for a user
CREATE OR REPLACE FUNCTION public.create_ccoin_card_for_user(
  p_user_id uuid,
  p_str_domain text,
  p_str_wallet text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
  v_domain := COALESCE(p_str_domain, 'user');
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

-- Function to create Visa card for a user
CREATE OR REPLACE FUNCTION public.create_visa_card_for_user(
  p_user_id uuid,
  p_str_domain text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_card_id uuid;
  v_last4 text;
  v_masked text;
BEGIN
  -- Check if user already has a Visa card
  SELECT id INTO v_card_id
  FROM prepaid_cards
  WHERE user_id = p_user_id AND network = 'visa'
  LIMIT 1;
  
  IF v_card_id IS NOT NULL THEN
    RETURN v_card_id;
  END IF;
  
  -- Generate card details
  v_last4 := lpad(floor(1000 + random() * 9000)::text, 4, '0');
  v_masked := '4xxxxxx******' || v_last4;
  
  -- Create Visa card
  INSERT INTO prepaid_cards (
    user_id,
    balance,
    card_type,
    currency,
    status,
    network,
    issuer,
    bin,
    card_last4,
    masked_card,
    domain_part
  ) VALUES (
    p_user_id,
    0,
    'virtual',
    'EUR',
    'active',
    'visa',
    'CCoin Finance',
    '4xxxxxx',
    v_last4,
    v_masked,
    p_str_domain
  )
  RETURNING id INTO v_card_id;
  
  RETURN v_card_id;
END;
$$;

-- RPC function for bulk IBAN and card creation (admin only)
CREATE OR REPLACE FUNCTION public.admin_bulk_create_banking(
  p_create_ibans boolean DEFAULT true,
  p_create_ccoin_cards boolean DEFAULT true,
  p_create_visa_cards boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  user_record RECORD;
  created_ibans integer := 0;
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
      -- Create IBAN if requested
      IF p_create_ibans THEN
        v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name);
        IF v_result IS NOT NULL THEN
          created_ibans := created_ibans + 1;
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
    'bulk_banking_creation',
    'banking_services',
    jsonb_build_object(
      'created_ibans', created_ibans,
      'created_ccoin_cards', created_ccoin_cards,
      'created_visa_cards', created_visa_cards,
      'skipped_users', skipped_users,
      'timestamp', now()
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'created_ibans', created_ibans,
    'created_ccoin_cards', created_ccoin_cards,
    'created_visa_cards', created_visa_cards,
    'skipped_users', skipped_users,
    'timestamp', now()
  );
END;
$$;

-- Update handle_new_user_signup to automatically create IBAN and cards
CREATE OR REPLACE FUNCTION public.handle_new_user_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  wallet_addr text;
  v_full_name text;
BEGIN
  -- Generate wallet address
  wallet_addr := 'arss_' || substr(md5(random()::text || clock_timestamp()::text), 1, 32);
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', 'User ' || substring(NEW.id::text, 1, 8));
  
  -- Create user profile
  INSERT INTO user_profiles (
    user_id,
    full_name,
    address,
    city,
    country,
    postal_code,
    email_address,
    str_domain_owned,
    str_domain_username,
    bsc_wallet_address,
    btc_wallet_address,
    status
  ) VALUES (
    NEW.id,
    v_full_name,
    'To be updated',
    'To be updated', 
    'To be updated',
    'To be updated',
    NEW.email,
    'To be updated',
    'To be updated',
    'To be updated',
    'To be updated',
    'pending'::account_status
  );

  -- Create user wallet
  INSERT INTO user_wallets (
    user_id,
    wallet_address,
    arss_balance
  ) VALUES (
    NEW.id,
    wallet_addr,
    1000.00
  );

  -- Assign default user role
  INSERT INTO user_roles (
    user_id,
    role,
    created_by
  ) VALUES (
    NEW.id,
    'user'::app_role,
    NEW.id
  )
  ON CONFLICT (user_id, role) DO NOTHING;
  
  -- Auto-create CCoin IBAN (deferred to avoid blocking signup)
  PERFORM create_ccoin_iban_for_user(NEW.id, v_full_name);
  
  -- Auto-create CCoin network card (deferred)
  PERFORM create_ccoin_card_for_user(NEW.id, 'To be updated', wallet_addr);
  
  -- Auto-create Visa card (deferred)
  PERFORM create_visa_card_for_user(NEW.id, 'To be updated');

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'Error in handle_new_user_signup: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- Get member banking overview (admin only)
CREATE OR REPLACE FUNCTION public.get_member_banking_overview()
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email_address text,
  str_domain text,
  has_iban boolean,
  has_ccoin_card boolean,
  has_visa_card boolean,
  total_cards integer,
  account_status text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Only admins can access
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;
  
  RETURN QUERY
  SELECT 
    up.user_id,
    up.full_name,
    up.email_address,
    up.str_domain_owned as str_domain,
    EXISTS(SELECT 1 FROM iban_accounts ia WHERE ia.user_id = up.user_id) as has_iban,
    EXISTS(SELECT 1 FROM prepaid_cards pc WHERE pc.user_id = up.user_id AND pc.network = 'ccoin') as has_ccoin_card,
    EXISTS(SELECT 1 FROM prepaid_cards pc WHERE pc.user_id = up.user_id AND pc.network = 'visa') as has_visa_card,
    (SELECT COUNT(*)::integer FROM prepaid_cards pc WHERE pc.user_id = up.user_id) as total_cards,
    up.status::text as account_status,
    up.created_at
  FROM user_profiles up
  WHERE up.status = 'approved'
  ORDER BY up.created_at DESC;
END;
$$;