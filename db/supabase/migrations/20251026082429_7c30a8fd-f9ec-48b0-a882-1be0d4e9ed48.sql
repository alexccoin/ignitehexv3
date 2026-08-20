-- Fix RLS policies for ccoin_bank_applications to prevent infinite recursion
-- Replace direct user_roles queries with has_role() security definer function

-- Drop existing policies that use direct user_roles queries
DROP POLICY IF EXISTS "Admins can update CCoin Bank applications" ON ccoin_bank_applications;
DROP POLICY IF EXISTS "Admins can view all CCoin Bank applications" ON ccoin_bank_applications;

-- Recreate with has_role() function to avoid recursion
CREATE POLICY "Admins can update CCoin Bank applications" 
ON ccoin_bank_applications 
FOR UPDATE 
USING (has_role(auth.uid(), 'admin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can view all CCoin Bank applications" 
ON ccoin_bank_applications 
FOR SELECT 
USING (has_role(auth.uid(), 'admin'::app_role));