-- Create admin_get_complete_banking_overview to power AdminBankingOverview page
-- Returns a comprehensive view of users with their IBANs and cards
CREATE OR REPLACE FUNCTION public.admin_get_complete_banking_overview()
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email_address text,
  str_domain text,
  eur_iban_id uuid,
  eur_iban text,
  chf_iban_id uuid,
  chf_iban text,
  gbp_iban_id uuid,
  gbp_iban text,
  ccoin_card_id uuid,
  ccoin_card_masked text,
  visa_card_id uuid,
  visa_card_masked text,
  banking_status text,
  created_at timestamptz
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
    up.user_id,
    up.full_name,
    up.email_address,
    up.str_domain_owned AS str_domain,
    cbp.eur_iban_id,
    i_eur.iban AS eur_iban,
    cbp.chf_iban_id,
    i_chf.iban AS chf_iban,
    cbp.gbp_iban_id,
    i_gbp.iban AS gbp_iban,
    cbp.ccoin_card_id,
    pc_ccoin.masked_card AS ccoin_card_masked,
    cbp.visa_card_id,
    pc_visa.masked_card AS visa_card_masked,
    cbp.banking_status,
    up.created_at
  FROM public.user_profiles up
  LEFT JOIN public.ccoin_banking_profiles cbp ON cbp.user_id = up.user_id
  LEFT JOIN public.iban_accounts i_eur ON i_eur.id = cbp.eur_iban_id
  LEFT JOIN public.iban_accounts i_chf ON i_chf.id = cbp.chf_iban_id
  LEFT JOIN public.iban_accounts i_gbp ON i_gbp.id = cbp.gbp_iban_id
  LEFT JOIN public.prepaid_cards pc_ccoin ON pc_ccoin.id = cbp.ccoin_card_id
  LEFT JOIN public.prepaid_cards pc_visa ON pc_visa.id = cbp.visa_card_id
  WHERE up.status = 'approved'
  ORDER BY up.full_name NULLS LAST;
END;
$$;

-- Ensure RLS safe usage via SECURITY DEFINER and explicit admin check above
-- Grant execute to authenticated (the function enforces admin access inside)
GRANT EXECUTE ON FUNCTION public.admin_get_complete_banking_overview() TO authenticated;