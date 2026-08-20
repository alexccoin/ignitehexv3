-- Fix trigger issues blocking card creation
-- Drop incorrectly applied triggers
DROP TRIGGER IF EXISTS prevent_plaintext_data_iban ON iban_accounts;

-- The prevent_plaintext_recovery_words function should only apply to user_profiles
-- Ensure it's only triggered there
DROP TRIGGER IF EXISTS prevent_plaintext_recovery_words_trigger ON user_profiles;

CREATE TRIGGER prevent_plaintext_recovery_words_trigger
  BEFORE INSERT OR UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_plaintext_recovery_words();

-- Update account_type to support personal, business, corporate
-- First check if we need to modify the column
DO $$
BEGIN
  -- Add account_type enum if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_type_enum') THEN
    CREATE TYPE account_type_enum AS ENUM ('personal', 'business', 'corporate');
  END IF;
END $$;

-- Add new fields to iban_accounts for account types
ALTER TABLE iban_accounts
  ADD COLUMN IF NOT EXISTS merchant_account boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS pos_enabled boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS account_category text DEFAULT 'personal' CHECK (account_category IN ('personal', 'business', 'corporate'));

-- Add new fields to prepaid_cards to support physical cards and card status
ALTER TABLE prepaid_cards
  ADD COLUMN IF NOT EXISTS card_status text DEFAULT 'active' CHECK (card_status IN ('active', 'pending', 'blocked', 'expired')),
  ADD COLUMN IF NOT EXISTS physical_card boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS shipping_status text CHECK (shipping_status IN ('pending', 'shipped', 'delivered', NULL));

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_iban_accounts_account_category ON iban_accounts(account_category);
CREATE INDEX IF NOT EXISTS idx_iban_accounts_merchant ON iban_accounts(merchant_account) WHERE merchant_account = true;
CREATE INDEX IF NOT EXISTS idx_prepaid_cards_physical ON prepaid_cards(physical_card) WHERE physical_card = true;
CREATE INDEX IF NOT EXISTS idx_prepaid_cards_status ON prepaid_cards(card_status);

-- Log the fix
INSERT INTO security_audit_log (user_id, action, resource_type, details)
SELECT 
  auth.uid(),
  'trigger_fix_applied',
  'database_schema',
  jsonb_build_object(
    'action', 'Fixed prevent_plaintext triggers and added account type support',
    'tables_affected', ARRAY['iban_accounts', 'prepaid_cards', 'user_profiles'],
    'timestamp', now()
  )
WHERE auth.uid() IS NOT NULL;