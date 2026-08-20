CREATE OR REPLACE FUNCTION public.create_complete_banking_via_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile record;
  v_up record;
  v_eur uuid;
  v_chf uuid;
  v_gbp uuid;
  v_ccoin_card uuid;
  v_visa_card uuid;
BEGIN
  -- Fetch basic user info
  SELECT user_id, full_name, email_address, str_domain_owned AS str_domain
  INTO v_up
  FROM public.user_profiles
  WHERE user_id = p_user_id;

  -- Ensure banking profile exists
  SELECT * INTO v_profile
  FROM public.ccoin_banking_profiles
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.ccoin_banking_profiles (
      user_id, full_name, email_address, banking_status, kyc_status, created_at, updated_at,
      eur_iban_created, chf_iban_created, gbp_iban_created,
      ccoin_card_created, visa_card_created,
      str_domain
    ) VALUES (
      p_user_id, COALESCE(v_up.full_name, 'Unknown'), COALESCE(v_up.email_address, 'unknown@example.com'),
      'active', 'pending', now(), now(),
      false, false, false,
      false, false,
      v_up.str_domain
    );
  ELSE
    UPDATE public.ccoin_banking_profiles
    SET full_name = COALESCE(v_up.full_name, full_name),
        email_address = COALESCE(v_up.email_address, email_address),
        str_domain = COALESCE(v_up.str_domain, str_domain),
        updated_at = now()
    WHERE user_id = p_user_id;
  END IF;

  -- Create missing IBANs (EUR/CHF/GBP) with explicit casts to avoid variadic unknown resolution
  v_eur := public.create_iban_for_user(p_user_id, 'EUR'::text, NULL::text);
  v_chf := public.create_iban_for_user(p_user_id, 'CHF'::text, NULL::text);
  v_gbp := public.create_iban_for_user(p_user_id, 'GBP'::text, NULL::text);

  -- Create cards
  v_ccoin_card := public.create_ccoin_card_for_user(p_user_id, v_up.str_domain);
  v_visa_card := public.create_visa_card_for_user(p_user_id, v_up.str_domain);

  UPDATE public.ccoin_banking_profiles
  SET eur_iban_id = COALESCE(eur_iban_id, v_eur),
      chf_iban_id = COALESCE(chf_iban_id, v_chf),
      gbp_iban_id = COALESCE(gbp_iban_id, v_gbp),
      eur_iban_created = true,
      chf_iban_created = true,
      gbp_iban_created = true,
      ccoin_card_id = COALESCE(ccoin_card_id, v_ccoin_card),
      visa_card_id = COALESCE(visa_card_id, v_visa_card),
      ccoin_card_created = true,
      visa_card_created = true,
      last_banking_sync = now(),
      updated_at = now()
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'iban_ids', jsonb_build_object('eur', v_eur, 'chf', v_chf, 'gbp', v_gbp),
    'card_ids', jsonb_build_object('ccoin', v_ccoin_card, 'visa', v_visa_card),
    'timestamp', now()
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'user_id', p_user_id, 'timestamp', now());
END;
$$;