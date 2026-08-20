-- Security Fix: Replace recursive RLS policies on ccoin_bank_applications
-- This migration fixes infinite recursion risk by using secure has_role() function

-- Drop existing problematic policies
DROP POLICY IF EXISTS "Admins can view all CCoin Bank applications" ON ccoin_bank_applications;
DROP POLICY IF EXISTS "Admins can update CCoin Bank applications" ON ccoin_bank_applications;

-- Create secure policies using has_role() function instead of direct user_roles queries
CREATE POLICY "Admins can view all CCoin Bank applications"
ON ccoin_bank_applications FOR SELECT
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update CCoin Bank applications"
ON ccoin_bank_applications FOR UPDATE
USING (has_role(auth.uid(), 'admin'))
WITH CHECK (has_role(auth.uid(), 'admin'));