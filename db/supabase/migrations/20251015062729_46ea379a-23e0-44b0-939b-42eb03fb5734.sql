-- Create masked, valid-looking IBAN generator and banking creation helpers

-- 1) Create or replace helper to create an IBAN per user/currency
CREATE OR REPLACE FUNCTION public.create_iban_for_user(
  p_user_id uuid,
  p_currency text,
  p_country text DEFAULT 'CH',
  p_bic text DEFAULT 'CCFINCHZ'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing uuid;
  v_id uuid;
  v_checksum text;
  v_account text;
  v_iban text;
BEGIN
  -- Reuse latest existing IBAN for this currency if present
  SELECT id INTO v_existing
  FROM public.iban_accounts
  WHERE user_id = p_user_id AND currency = p_currency
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Generate a valid-looking IBAN: CC + 2 digits + 18 digits (alphanumeric allowed but keep numeric to simplify)
  v_checksum := lpad(((10 + floor(random()*90))::int)::text, 2, '0');
  v_account  := lpad(((floor(random()*1e10))::bigint)::text, 10, '0') ||
                lpad(((floor(random()*1e8))::bigint)::text, 8, '0');
  v_iban := upper(p_country) || v_checksum || v_account; -- e.g., CH23 + 18 digits

  INSERT INTO public.iban_accounts (
    user_id, iban, bic, currency, is_data_encrypted, created_at, updated_at
  ) VALUES (
    p_user_id, v_iban, p_bic, p_currency, true, now(), now()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 2) Create or replace helper to create a CCoin virtual card starting with str.
CREATE OR REPLACE FUNCTION public.create_ccoin_card_for_user(
  p_user_id uuid,
  p_str_domain text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing uuid;
  v_id uuid;
  v_last4 text;
  v_masked text;
  v_domain_part text := COALESCE(p_str_domain, 'user');
BEGIN
  SELECT id INTO v_existing
  FROM public.prepaid_cards
  WHERE user_id = p_user_id AND network = 'ccoin'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_last4 := lpad((1000 + floor(random() * 9000))::int::text, 4, '0');
  v_masked := 'str.' || v_domain_part || ' ****' || v_last4;

  INSERT INTO public.prepaid_cards (
    user_id, balance, card_type, currency, status, network, issuer,
    bin, card_last4, masked_card, domain_part
  ) VALUES (
    p_user_id, 0, 'virtual', 'CCOIN', 'active', 'ccoin', 'CCoin Finance',
    '620000', v_last4, v_masked, v_domain_part
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 3) Create or replace main orchestrator to ensure complete banking for a user
CREATE OR REPLACE FUNCTION public.create_complete_banking_via_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile RECORD;
  v_cbp RECORD;
  v_eur_iban uuid;
  v_chf_iban uuid;
  v_gbp_iban uuid;
  v_ccoin_card uuid;
  v_visa_card uuid;
BEGIN
  -- Load user profile
  SELECT user_id, full_name, email_address, str_domain_owned
  INTO v_profile
  FROM public.user_profiles
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'profile_not_found', 'user_id', p_user_id);
  END IF;

  -- Ensure banking profile row exists
  INSERT INTO public.ccoin_banking_profiles (
    user_id, full_name, email_address, str_domain, banking_status
  ) VALUES (
    p_user_id, v_profile.full_name, v_profile.email_address, v_profile.str_domain_owned, 'active'
  ) ON CONFLICT (user_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email_address = EXCLUDED.email_address,
    str_domain = EXCLUDED.str_domain,
    updated_at = now()
  RETURNING * INTO v_cbp;

  -- Create IBANs per currency (use CH for CHF, DE for EUR, GB for GBP)
  v_eur_iban := COALESCE(v_cbp.eur_iban_id, public.create_iban_for_user(p_user_id, 'EUR', 'DE'));
  v_chf_iban := COALESCE(v_cbp.chf_iban_id, public.create_iban_for_user(p_user_id, 'CHF', 'CH'));
  v_gbp_iban := COALESCE(v_cbp.gbp_iban_id, public.create_iban_for_user(p_user_id, 'GBP', 'GB'));

  -- Create cards
  v_ccoin_card := COALESCE(v_cbp.ccoin_card_id, public.create_ccoin_card_for_user(p_user_id, v_profile.str_domain_owned));
  v_visa_card  := COALESCE(v_cbp.visa_card_id,  public.create_visa_card_for_user(p_user_id, v_profile.str_domain_owned));

  -- Update banking profile with created assets
  UPDATE public.ccoin_banking_profiles
  SET 
    eur_iban_id = v_eur_iban,
    chf_iban_id = v_chf_iban,
    gbp_iban_id = v_gbp_iban,
    eur_iban_created = true,
    chf_iban_created = true,
    gbp_iban_created = true,
    ccoin_card_id = v_ccoin_card,
    visa_card_id = v_visa_card,
    ccoin_card_created = true,
    visa_card_created = true,
    last_banking_sync = now(),
    updated_at = now()
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'eur_iban_id', v_eur_iban,
    'chf_iban_id', v_chf_iban,
    'gbp_iban_id', v_gbp_iban,
    'ccoin_card_id', v_ccoin_card,
    'visa_card_id', v_visa_card,
    'timestamp', now()
  );
END;
$$;