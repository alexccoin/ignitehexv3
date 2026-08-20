-- Add account type and business fields to ccoin_banking_profiles
ALTER TABLE ccoin_banking_profiles 
ADD COLUMN IF NOT EXISTS account_type text DEFAULT 'personal' CHECK (account_type IN ('personal', 'business', 'corporate')),
ADD COLUMN IF NOT EXISTS company_name text,
ADD COLUMN IF NOT EXISTS company_registration_number text,
ADD COLUMN IF NOT EXISTS tax_id text,
ADD COLUMN IF NOT EXISTS business_type text,
ADD COLUMN IF NOT EXISTS business_address jsonb,
ADD COLUMN IF NOT EXISTS authorized_signatories jsonb DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS corporate_structure jsonb;

-- Add account type to applications
ALTER TABLE ccoin_bank_applications
ADD COLUMN IF NOT EXISTS account_type text DEFAULT 'personal' CHECK (account_type IN ('personal', 'business', 'corporate')),
ADD COLUMN IF NOT EXISTS company_name text,
ADD COLUMN IF NOT EXISTS company_registration_number text,
ADD COLUMN IF NOT EXISTS requested_products jsonb DEFAULT '{"iban_eur": false, "iban_chf": false, "iban_gbp": false, "ccoin_card": false, "visa_card": false}'::jsonb;

-- Add more fields to user_plain_ibans for better tracking
ALTER TABLE user_plain_ibans
ADD COLUMN IF NOT EXISTS account_name text,
ADD COLUMN IF NOT EXISTS account_type text DEFAULT 'personal',
ADD COLUMN IF NOT EXISTS balance numeric DEFAULT 0,
ADD COLUMN IF NOT EXISTS status text DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'closed')),
ADD COLUMN IF NOT EXISTS daily_limit numeric DEFAULT 10000,
ADD COLUMN IF NOT EXISTS monthly_limit numeric DEFAULT 100000;

-- Add more fields to user_plain_ccoin_cards
ALTER TABLE user_plain_ccoin_cards
ADD COLUMN IF NOT EXISTS cardholder_name text,
ADD COLUMN IF NOT EXISTS account_type text DEFAULT 'personal',
ADD COLUMN IF NOT EXISTS balance numeric DEFAULT 0,
ADD COLUMN IF NOT EXISTS daily_limit numeric DEFAULT 5000,
ADD COLUMN IF NOT EXISTS monthly_limit numeric DEFAULT 50000,
ADD COLUMN IF NOT EXISTS status text DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'blocked', 'closed'));

COMMENT ON COLUMN ccoin_banking_profiles.account_type IS 'Type of banking account: personal, business, or corporate';
COMMENT ON COLUMN ccoin_banking_profiles.company_name IS 'Company name for business/corporate accounts';
COMMENT ON COLUMN ccoin_banking_profiles.authorized_signatories IS 'List of authorized signatories for business/corporate accounts';
COMMENT ON COLUMN ccoin_bank_applications.requested_products IS 'Banking products requested by the applicant';