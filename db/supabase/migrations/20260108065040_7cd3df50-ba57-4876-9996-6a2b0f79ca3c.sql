
-- =============================================
-- SECURITY FIX: Safe RLS Policy Updates Only
-- NO data changes, NO table structure changes
-- =============================================

-- 1. Enable RLS on praeco_peers (currently disabled)
ALTER TABLE public.praeco_peers ENABLE ROW LEVEL SECURITY;

-- Add policies for praeco_peers - users can only see their own peers
-- Note: user_id is TEXT type, so cast auth.uid() to text
CREATE POLICY "Users can view their own peers"
ON public.praeco_peers
FOR SELECT
USING (auth.uid()::text = user_id);

CREATE POLICY "Users can manage their own peers"
ON public.praeco_peers
FOR ALL
USING (auth.uid()::text = user_id)
WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Admins can manage all peers"
ON public.praeco_peers
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
);

-- 2. Fix domain_marketplace_listings - create a view-safe policy
-- Drop the overly permissive SELECT policy
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.domain_marketplace_listings;

-- Create new policy - authenticated users can view active listings or their own
CREATE POLICY "Authenticated users can view active listings"
ON public.domain_marketplace_listings
FOR SELECT
USING (
  auth.uid() IS NOT NULL 
  AND (
    status = 'active'
    OR seller_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'::app_role
    )
  )
);

-- 3. Fix support_ticket_fix_history - remove the overly permissive policy
DROP POLICY IF EXISTS "Service role can manage fix history" ON public.support_ticket_fix_history;

-- Add admin-only management policy
CREATE POLICY "Admins can manage fix history"
ON public.support_ticket_fix_history
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
);
