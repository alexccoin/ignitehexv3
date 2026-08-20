
-- Add more permissive RLS policy for users to view their own IBAN accounts
-- The existing "Users can view own IBAN accounts secure" has a strange condition with auth.uid() IS NOT NULL check

-- Drop and recreate simpler user policy
DROP POLICY IF EXISTS "Users can view own IBAN accounts secure" ON iban_accounts;

CREATE POLICY "Users can view own IBAN accounts"
  ON iban_accounts FOR SELECT
  USING (auth.uid() = user_id);

-- Same for prepaid_cards
DROP POLICY IF EXISTS "Users can view own prepaid cards secure" ON prepaid_cards;

CREATE POLICY "Users can view own prepaid cards"
  ON prepaid_cards FOR SELECT
  USING (auth.uid() = user_id);

-- Also ensure admin policies exist on prepaid_cards
DROP POLICY IF EXISTS "Admins can view all prepaid cards" ON prepaid_cards;
CREATE POLICY "Admins can view all prepaid cards"
  ON prepaid_cards FOR SELECT
  USING (is_admin(auth.uid()));
