-- Create sync function to update ccoin_banking_profiles from current state
CREATE OR REPLACE FUNCTION sync_ccoin_banking_profiles()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  synced_count INTEGER := 0;
  user_record RECORD;
BEGIN
  -- Only admins can sync
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  -- Update all profiles with current banking status
  FOR user_record IN
    SELECT 
      up.user_id,
      up.full_name,
      up.email_address,
      up.str_domain_owned as str_domain,
      up.str_wallet_address,
      -- EUR IBAN
      (SELECT ia.id FROM iban_accounts ia WHERE ia.user_id = up.user_id AND ia.currency = 'EUR' LIMIT 1) as eur_iban_id,
      EXISTS(SELECT 1 FROM iban_accounts ia WHERE ia.user_id = up.user_id AND ia.currency = 'EUR') as eur_iban_created,
      -- CHF IBAN
      (SELECT ia.id FROM iban_accounts ia WHERE ia.user_id = up.user_id AND ia.currency = 'CHF' LIMIT 1) as chf_iban_id,
      EXISTS(SELECT 1 FROM iban_accounts ia WHERE ia.user_id = up.user_id AND ia.currency = 'CHF') as chf_iban_created,
      -- GBP IBAN
      (SELECT ia.id FROM iban_accounts ia WHERE ia.user_id = up.user_id AND ia.currency = 'GBP' LIMIT 1) as gbp_iban_id,
      EXISTS(SELECT 1 FROM iban_accounts ia WHERE ia.user_id = up.user_id AND ia.currency = 'GBP') as gbp_iban_created,
      -- CCoin Card
      (SELECT pc.id FROM prepaid_cards pc WHERE pc.user_id = up.user_id AND pc.network = 'ccoin' LIMIT 1) as ccoin_card_id,
      EXISTS(SELECT 1 FROM prepaid_cards pc WHERE pc.user_id = up.user_id AND pc.network = 'ccoin') as ccoin_card_created,
      -- Visa Card
      (SELECT pc.id FROM prepaid_cards pc WHERE pc.user_id = up.user_id AND pc.network = 'visa' LIMIT 1) as visa_card_id,
      EXISTS(SELECT 1 FROM prepaid_cards pc WHERE pc.user_id = up.user_id AND pc.network = 'visa') as visa_card_created
    FROM user_profiles up
    WHERE up.status = 'approved'
  LOOP
    -- Upsert banking profile
    INSERT INTO ccoin_banking_profiles (
      user_id,
      full_name,
      email_address,
      str_domain,
      str_wallet_address,
      eur_iban_id,
      eur_iban_created,
      chf_iban_id,
      chf_iban_created,
      gbp_iban_id,
      gbp_iban_created,
      ccoin_card_id,
      ccoin_card_created,
      visa_card_id,
      visa_card_created,
      last_banking_sync
    ) VALUES (
      user_record.user_id,
      user_record.full_name,
      user_record.email_address,
      user_record.str_domain,
      user_record.str_wallet_address,
      user_record.eur_iban_id,
      user_record.eur_iban_created,
      user_record.chf_iban_id,
      user_record.chf_iban_created,
      user_record.gbp_iban_id,
      user_record.gbp_iban_created,
      user_record.ccoin_card_id,
      user_record.ccoin_card_created,
      user_record.visa_card_id,
      user_record.visa_card_created,
      now()
    )
    ON CONFLICT (user_id) 
    DO UPDATE SET
      full_name = EXCLUDED.full_name,
      email_address = EXCLUDED.email_address,
      str_domain = EXCLUDED.str_domain,
      str_wallet_address = EXCLUDED.str_wallet_address,
      eur_iban_id = EXCLUDED.eur_iban_id,
      eur_iban_created = EXCLUDED.eur_iban_created,
      chf_iban_id = EXCLUDED.chf_iban_id,
      chf_iban_created = EXCLUDED.chf_iban_created,
      gbp_iban_id = EXCLUDED.gbp_iban_id,
      gbp_iban_created = EXCLUDED.gbp_iban_created,
      ccoin_card_id = EXCLUDED.ccoin_card_id,
      ccoin_card_created = EXCLUDED.ccoin_card_created,
      visa_card_id = EXCLUDED.visa_card_id,
      visa_card_created = EXCLUDED.visa_card_created,
      last_banking_sync = now(),
      updated_at = now();

    synced_count := synced_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'synced_count', synced_count,
    'timestamp', now()
  );
END;
$$;

-- New admin function to get centralized banking overview
CREATE OR REPLACE FUNCTION get_ccoin_banking_overview()
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email_address text,
  str_domain text,
  has_eur_iban boolean,
  has_chf_iban boolean,
  has_gbp_iban boolean,
  has_any_iban boolean,
  has_ccoin_card boolean,
  has_visa_card boolean,
  total_cards integer,
  banking_status text,
  kyc_status text,
  last_sync timestamp with time zone,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only admins can access
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT 
    cbp.user_id,
    cbp.full_name,
    cbp.email_address,
    cbp.str_domain,
    cbp.eur_iban_created as has_eur_iban,
    cbp.chf_iban_created as has_chf_iban,
    cbp.gbp_iban_created as has_gbp_iban,
    (cbp.eur_iban_created OR cbp.chf_iban_created OR cbp.gbp_iban_created) as has_any_iban,
    cbp.ccoin_card_created as has_ccoin_card,
    cbp.visa_card_created as has_visa_card,
    (CASE WHEN cbp.ccoin_card_created THEN 1 ELSE 0 END + 
     CASE WHEN cbp.visa_card_created THEN 1 ELSE 0 END)::integer as total_cards,
    cbp.banking_status,
    cbp.kyc_status,
    cbp.last_banking_sync as last_sync,
    cbp.created_at
  FROM ccoin_banking_profiles cbp
  ORDER BY cbp.full_name;
END;
$$;