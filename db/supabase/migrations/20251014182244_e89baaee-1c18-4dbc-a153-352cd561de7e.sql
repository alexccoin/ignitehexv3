-- Make bulk creation resilient per step so one failure doesn't block others
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
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  FOR user_record IN
    SELECT user_id, full_name, str_domain_owned, str_wallet_address
    FROM user_profiles
    WHERE status = 'approved'
    ORDER BY created_at
  LOOP
    BEGIN
      -- IBANs (each currency isolated so one failure won't stop the rest)
      IF p_create_ibans THEN
        BEGIN
          v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name, 'EUR');
          IF v_result IS NOT NULL THEN created_eur_ibans := created_eur_ibans + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE LOG 'EUR IBAN failed for user %: %', user_record.user_id, SQLERRM;
        END;

        BEGIN
          v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name, 'CHF');
          IF v_result IS NOT NULL THEN created_chf_ibans := created_chf_ibans + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE LOG 'CHF IBAN failed for user %: %', user_record.user_id, SQLERRM;
        END;

        BEGIN
          v_result := create_ccoin_iban_for_user(user_record.user_id, user_record.full_name, 'GBP');
          IF v_result IS NOT NULL THEN created_gbp_ibans := created_gbp_ibans + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE LOG 'GBP IBAN failed for user %: %', user_record.user_id, SQLERRM;
        END;
      END IF;

      -- CCoin card
      IF p_create_ccoin_cards THEN
        BEGIN
          v_result := create_ccoin_card_for_user(
            user_record.user_id,
            user_record.str_domain_owned,
            user_record.str_wallet_address
          );
          IF v_result IS NOT NULL THEN created_ccoin_cards := created_ccoin_cards + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE LOG 'CCoin card failed for user %: %', user_record.user_id, SQLERRM;
        END;
      END IF;

      -- Visa card
      IF p_create_visa_cards THEN
        BEGIN
          v_result := create_visa_card_for_user(user_record.user_id, user_record.str_domain_owned);
          IF v_result IS NOT NULL THEN created_visa_cards := created_visa_cards + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE LOG 'Visa card failed for user %: %', user_record.user_id, SQLERRM;
        END;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      skipped_users := skipped_users + 1;
      RAISE LOG 'User-level error for %: %', user_record.user_id, SQLERRM;
    END;
  END LOOP;

  INSERT INTO security_audit_log (user_id, action, resource_type, details)
  VALUES (
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