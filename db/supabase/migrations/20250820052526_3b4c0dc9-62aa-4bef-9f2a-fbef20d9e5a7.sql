-- FINAL SECURITY FIX: Address Liquidity Pool Data Access Warning

-- Restrict liquidity_pools access to users with actual positions in pools
DROP POLICY IF EXISTS "Authenticated users can view liquidity pools" ON public.liquidity_pools;

-- Create more restrictive policy for liquidity pools
CREATE POLICY "Users can view pools they have positions in" ON public.liquidity_pools
FOR SELECT USING (
  auth.uid() IS NOT NULL AND (
    -- Allow admins to see all pools
    is_admin(auth.uid()) OR
    -- Allow users to see pools they have positions/transactions in
    EXISTS (
      SELECT 1 FROM liquidity_transactions lt 
      WHERE lt.pool_id = liquidity_pools.id 
      AND lt.user_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM user_liquidity_positions ulp 
      WHERE ulp.pool_id = liquidity_pools.id 
      AND ulp.user_id = auth.uid()
    )
  )
);

-- Add a public view for basic pool information (non-sensitive data only)
CREATE OR REPLACE FUNCTION get_public_pool_info()
RETURNS TABLE(
  id uuid,
  pool_name text,
  pool_symbol text,
  pool_type text,
  description text,
  is_active boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Public information only - no sensitive trading data like liquidity amounts or APY
  RETURN QUERY
  SELECT 
    lp.id,
    lp.pool_name,
    lp.pool_symbol,
    lp.pool_type,
    lp.description,
    lp.is_active
  FROM liquidity_pools lp
  WHERE lp.is_active = true
  ORDER BY lp.pool_name;
END;
$$;