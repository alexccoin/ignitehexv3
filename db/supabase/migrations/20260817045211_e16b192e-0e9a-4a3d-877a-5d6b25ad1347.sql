CREATE OR REPLACE FUNCTION public.v2_import_legacy_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_profile record;
  v_email text;
  v_inserted int := 0;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT * INTO v_profile FROM public.user_profiles WHERE user_id = p_user_id LIMIT 1;
  SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;

  INSERT INTO public.v2_accounts (user_id, status, email, full_name, country_of_residence, city, postal_code, address_line1, str_domain)
  VALUES (
    p_user_id,
    'draft',
    COALESCE(v_email, v_profile.email_address),
    v_profile.full_name,
    v_profile.country,
    v_profile.city,
    v_profile.postal_code,
    v_profile.address,
    NULLIF(v_profile.str_domain_username, '')
  )
  ON CONFLICT (user_id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, public.v2_accounts.email),
    full_name = COALESCE(public.v2_accounts.full_name, EXCLUDED.full_name),
    country_of_residence = COALESCE(public.v2_accounts.country_of_residence, EXCLUDED.country_of_residence),
    city = COALESCE(public.v2_accounts.city, EXCLUDED.city),
    postal_code = COALESCE(public.v2_accounts.postal_code, EXCLUDED.postal_code),
    address_line1 = COALESCE(public.v2_accounts.address_line1, EXCLUDED.address_line1),
    str_domain = COALESCE(public.v2_accounts.str_domain, EXCLUDED.str_domain),
    updated_at = now()
  RETURNING id INTO v_account_id;

  IF v_account_id IS NULL THEN
    SELECT id INTO v_account_id FROM public.v2_accounts WHERE user_id = p_user_id;
  END IF;

  -- idempotent: clear previous import
  DELETE FROM public.v2_verified_assets WHERE user_id = p_user_id AND reference = 'legacy-import';

  -- fiat balances
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'fiat', currency, currency || ' balance', balance, 'legacy-import', auth.uid()
  FROM public.fiat_wallets WHERE user_id = p_user_id AND balance > 0;

  -- crypto / token balances
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'token', token_type, token_type || ' wallet', balance, 'legacy-import', auth.uid()
  FROM public.crypto_wallets WHERE user_id = p_user_id AND balance > 0;

  -- STR shares
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'token', 'STR', 'STR shares (wallet)', SUM(balance), 'legacy-import', auth.uid()
  FROM public.user_str_shares WHERE user_id = p_user_id GROUP BY user_id HAVING SUM(balance) > 0;

  -- staking
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'token', 'STR', 'Staked STR (' || COUNT(*) || ' pools)', SUM(staked_amount), 'legacy-import', auth.uid()
  FROM public.user_staking_pools WHERE user_id = p_user_id AND staked_amount > 0 GROUP BY user_id;

  -- vesting
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'token', token_type, 'Vesting ' || token_type, SUM(amount), 'legacy-import', auth.uid()
  FROM public.vesting_tokens WHERE user_id = p_user_id AND amount > 0 GROUP BY token_type;

  -- SAFE equity
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'equity', 'SAFE', 'SAFE credited shares', SUM(COALESCE(credited_shares, total_shares, 0)), 'legacy-import', auth.uid()
  FROM public.safe_purchases WHERE user_id = p_user_id AND credited_at IS NOT NULL GROUP BY user_id;

  -- STR domains
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'str_domain', 'DOMAINS', 'STR domains owned', COUNT(*), 'legacy-import', auth.uid()
  FROM public.str_domains WHERE user_id = p_user_id AND status = 'minted' HAVING COUNT(*) > 0;

  -- nodes
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'node', 'SUPERNODE', 'Supernodes', COUNT(*), 'legacy-import', auth.uid()
  FROM public.supernodes WHERE user_id = p_user_id HAVING COUNT(*) > 0;

  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'node', 'STARW', 'STARW nodes', COUNT(*), 'legacy-import', auth.uid()
  FROM public.starw_nodes WHERE user_id = p_user_id HAVING COUNT(*) > 0;

  -- banking products
  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'banking', 'IBAN', 'IBAN accounts', COUNT(*), 'legacy-import', auth.uid()
  FROM public.iban_accounts WHERE user_id = p_user_id HAVING COUNT(*) > 0;

  INSERT INTO public.v2_verified_assets (account_id, user_id, category, asset_symbol, asset_label, amount, reference, verified_by)
  SELECT v_account_id, p_user_id, 'card', 'CARD', 'Issued cards', COUNT(*), 'legacy-import', auth.uid()
  FROM public.prepaid_cards WHERE user_id = p_user_id HAVING COUNT(*) > 0;

  SELECT COUNT(*) INTO v_inserted FROM public.v2_verified_assets WHERE user_id = p_user_id AND reference = 'legacy-import';

  -- service connections based on what exists
  INSERT INTO public.v2_service_connections (account_id, user_id, service, status, requested_at, connected_at)
  SELECT v_account_id, p_user_id, s.service, 'connected', now(), now()
  FROM (VALUES ('str_domains'), ('str_dome'), ('ccoin_finance'), ('ccoin_bank')) AS s(service)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.v2_service_connections c
    WHERE c.user_id = p_user_id AND c.service = s.service
  );

  RETURN jsonb_build_object('account_id', v_account_id, 'assets_imported', v_inserted);
END;
$$;

REVOKE ALL ON FUNCTION public.v2_import_legacy_account(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.v2_import_legacy_account(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.v2_import_legacy_account_by_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'Admin role required';
  END IF;

  SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(trim(p_email)) LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No user found for %', p_email;
  END IF;

  RETURN public.v2_import_legacy_account(v_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.v2_import_legacy_account_by_email(text) FROM public;
GRANT EXECUTE ON FUNCTION public.v2_import_legacy_account_by_email(text) TO authenticated;