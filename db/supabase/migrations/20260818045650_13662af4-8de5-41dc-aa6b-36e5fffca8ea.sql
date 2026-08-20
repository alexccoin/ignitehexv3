WITH latest AS (
  SELECT DISTINCT ON (user_id) *
  FROM public.user_profiles_updated
  WHERE submission_status = 'approved' AND user_id IS NOT NULL
  ORDER BY user_id, reviewed_at DESC NULLS LAST, created_at DESC
)
UPDATE public.user_profiles p
SET full_name = COALESCE(NULLIF(trim(l.full_name), ''), p.full_name),
    email_address = COALESCE(NULLIF(trim(l.email_address), ''), p.email_address),
    address = COALESCE(NULLIF(trim(l.address), ''), p.address),
    city = COALESCE(NULLIF(trim(l.city), ''), p.city),
    country = COALESCE(NULLIF(trim(l.country), ''), p.country),
    postal_code = COALESCE(NULLIF(trim(l.postal_code), ''), p.postal_code),
    str_domain_owned = COALESCE(NULLIF(trim(l.str_domain_owned), ''), p.str_domain_owned),
    bsc_wallet_address = COALESCE(NULLIF(trim(l.bsc_wallet_address), ''), p.bsc_wallet_address),
    btc_wallet_address = COALESCE(NULLIF(trim(l.btc_wallet_address), ''), p.btc_wallet_address),
    account_status = 'approved',
    profile_update_status = 'approved',
    updated_at = now()
FROM latest l
WHERE p.user_id = l.user_id;