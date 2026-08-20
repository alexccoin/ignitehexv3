-- Link existing IBANs and cards to ccoin_banking_profiles
-- Update EUR IBAN links
UPDATE ccoin_banking_profiles bp
SET eur_iban_id = ia.id,
    eur_iban_created = true
FROM iban_accounts ia
WHERE ia.user_id = bp.user_id 
  AND ia.currency = 'EUR'
  AND bp.eur_iban_id IS NULL;

-- Update CHF IBAN links
UPDATE ccoin_banking_profiles bp
SET chf_iban_id = ia.id,
    chf_iban_created = true
FROM iban_accounts ia
WHERE ia.user_id = bp.user_id 
  AND ia.currency = 'CHF'
  AND bp.chf_iban_id IS NULL;

-- Update GBP IBAN links
UPDATE ccoin_banking_profiles bp
SET gbp_iban_id = ia.id,
    gbp_iban_created = true
FROM iban_accounts ia
WHERE ia.user_id = bp.user_id 
  AND ia.currency = 'GBP'
  AND bp.gbp_iban_id IS NULL;

-- Update CCoin card links
UPDATE ccoin_banking_profiles bp
SET ccoin_card_id = pc.id,
    ccoin_card_created = true
FROM prepaid_cards pc
WHERE pc.user_id = bp.user_id 
  AND pc.network = 'ccoin'
  AND bp.ccoin_card_id IS NULL;

-- Update Visa card links
UPDATE ccoin_banking_profiles bp
SET visa_card_id = pc.id,
    visa_card_created = true
FROM prepaid_cards pc
WHERE pc.user_id = bp.user_id 
  AND pc.network = 'visa'
  AND bp.visa_card_id IS NULL;

-- Also update banking_status to 'active' for profiles with IBANs
UPDATE ccoin_banking_profiles
SET banking_status = 'active',
    updated_at = now()
WHERE eur_iban_id IS NOT NULL 
   OR chf_iban_id IS NOT NULL 
   OR gbp_iban_id IS NOT NULL;