ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS investor_classification text,
  ADD COLUMN IF NOT EXISTS source_of_funds text,
  ADD COLUMN IF NOT EXISTS source_of_wealth text,
  ADD COLUMN IF NOT EXISTS expected_monthly_volume_eur numeric,
  ADD COLUMN IF NOT EXISTS crypto_experience_level text,
  ADD COLUMN IF NOT EXISTS risk_acknowledged boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_pep boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS sanctions_declaration boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS tax_residency_country text,
  ADD COLUMN IF NOT EXISTS tax_identification_number text,
  ADD COLUMN IF NOT EXISTS mica_terms_accepted boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS mica_terms_version text,
  ADD COLUMN IF NOT EXISTS mica_terms_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS mica_approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS mica_profile_source_id uuid;

CREATE OR REPLACE FUNCTION public.v2_apply_profile_update(p_id uuid, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r public.user_profiles_updated%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.user_profiles_updated WHERE id = p_id;
  IF NOT FOUND OR r.user_id IS NULL THEN RETURN; END IF;

  IF lower(p_status) = 'approved' THEN
    UPDATE public.user_profiles p
    SET full_name = COALESCE(NULLIF(trim(r.full_name), ''), p.full_name),
        email_address = COALESCE(NULLIF(trim(r.email_address), ''), p.email_address),
        address = COALESCE(NULLIF(trim(r.address), ''), p.address),
        city = COALESCE(NULLIF(trim(r.city), ''), p.city),
        country = COALESCE(NULLIF(trim(r.country), ''), p.country),
        postal_code = COALESCE(NULLIF(trim(r.postal_code), ''), p.postal_code),
        str_domain_owned = COALESCE(NULLIF(trim(r.str_domain_owned), ''), p.str_domain_owned),
        bsc_wallet_address = COALESCE(NULLIF(trim(r.bsc_wallet_address), ''), p.bsc_wallet_address),
        btc_wallet_address = COALESCE(NULLIF(trim(r.btc_wallet_address), ''), p.btc_wallet_address),
        investor_classification = COALESCE(NULLIF(trim(r.investor_classification), ''), p.investor_classification),
        source_of_funds = COALESCE(NULLIF(trim(r.source_of_funds), ''), p.source_of_funds),
        source_of_wealth = COALESCE(NULLIF(trim(r.source_of_wealth), ''), p.source_of_wealth),
        expected_monthly_volume_eur = COALESCE(r.expected_monthly_volume_eur, p.expected_monthly_volume_eur),
        crypto_experience_level = COALESCE(NULLIF(trim(r.crypto_experience_level), ''), p.crypto_experience_level),
        risk_acknowledged = COALESCE(r.risk_acknowledged, p.risk_acknowledged),
        is_pep = COALESCE(r.is_pep, p.is_pep),
        sanctions_declaration = COALESCE(r.sanctions_declaration, p.sanctions_declaration),
        tax_residency_country = COALESCE(NULLIF(trim(r.tax_residency_country), ''), p.tax_residency_country),
        tax_identification_number = COALESCE(NULLIF(trim(r.tax_identification_number), ''), p.tax_identification_number),
        mica_terms_accepted = COALESCE(r.mica_terms_accepted, p.mica_terms_accepted),
        mica_terms_version = COALESCE(NULLIF(trim(r.mica_terms_version), ''), p.mica_terms_version),
        mica_terms_accepted_at = COALESCE(r.mica_terms_accepted_at, p.mica_terms_accepted_at),
        mica_approved_at = now(),
        mica_profile_source_id = r.id,
        account_status = 'approved',
        profile_update_status = 'approved',
        suspended_at = NULL,
        suspension_reason = NULL,
        updated_at = now()
    WHERE p.user_id = r.user_id;
  ELSIF lower(p_status) = 'suspended' THEN
    UPDATE public.user_profiles p
    SET account_status = 'suspended',
        profile_update_status = 'suspended',
        suspended_at = now(),
        suspension_reason = COALESCE(NULLIF(trim(r.admin_notes), ''), 'MiCA profile update suspended by compliance'),
        updated_at = now()
    WHERE p.user_id = r.user_id;
  ELSIF lower(p_status) IN ('rejected', 'declined') THEN
    UPDATE public.user_profiles p
    SET profile_update_status = 'rejected',
        updated_at = now()
    WHERE p.user_id = r.user_id;
  ELSE
    UPDATE public.user_profiles p
    SET profile_update_status = lower(p_status),
        updated_at = now()
    WHERE p.user_id = r.user_id;
  END IF;
END;
$$;