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
  SELECT user_id, full_name, email_address, str_domain_owned
  INTO v_profile
  FROM public.user_profiles
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'profile_not_found', 'user_id', p_user_id);
  END IF;

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

  -- Explicit type casts to avoid ambiguous function resolution
  v_eur_iban := COALESCE(v_cbp.eur_iban_id, public.create_iban_for_user(p_user_id, 'EUR'::text, 'DE'::text));
  v_chf_iban := COALESCE(v_cbp.chf_iban_id, public.create_iban_for_user(p_user_id, 'CHF'::text, 'CH'::text));
  v_gbp_iban := COALESCE(v_cbp.gbp_iban_id, public.create_iban_for_user(p_user_id, 'GBP'::text, 'GB'::text));

  v_ccoin_card := COALESCE(v_cbp.ccoin_card_id, public.create_ccoin_card_for_user(p_user_id, v_profile.str_domain_owned));
  v_visa_card  := COALESCE(v_cbp.visa_card_id,  public.create_visa_card_for_user(p_user_id, v_profile.str_domain_owned));

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