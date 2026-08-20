-- Add explicit admin SELECT policies for iban_accounts and prepaid_cards
-- The existing "Strict admin manage" policy with ALL cmd should work, but let's add explicit SELECT

-- Drop and recreate cleaner admin policies
DROP POLICY IF EXISTS "Admins can view all IBAN accounts" ON iban_accounts;
CREATE POLICY "Admins can view all IBAN accounts" ON iban_accounts
  FOR SELECT
  USING (is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can view all prepaid cards" ON prepaid_cards;
CREATE POLICY "Admins can view all prepaid cards" ON prepaid_cards
  FOR SELECT
  USING (is_admin(auth.uid()));