-- Fix RLS policy for enhanced_staking_pools to require authentication
DROP POLICY IF EXISTS "Anyone can view active enhanced pools" ON public.enhanced_staking_pools;

-- Create new policy that requires authentication
CREATE POLICY "Authenticated users can view active enhanced pools" 
ON public.enhanced_staking_pools 
FOR SELECT 
USING (
  auth.uid() IS NOT NULL AND 
  (status = 'active'::pool_status OR is_admin(auth.uid()))
);