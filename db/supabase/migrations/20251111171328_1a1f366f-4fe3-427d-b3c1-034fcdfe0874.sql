
-- Fix STARW purchases RLS to allow admins to create manual entries
-- Drop existing insert policy that's blocking admin manual entries
DROP POLICY IF EXISTS "Users can insert own STARW purchases" ON public.starw_purchases;

-- Recreate with admin support
CREATE POLICY "Users can insert own STARW purchases"
  ON public.starw_purchases
  FOR INSERT
  WITH CHECK (
    -- Users can insert their own purchases
    (auth.uid() = user_id) 
    OR 
    -- Admins can insert manual purchases (with null user_id)
    (is_admin(auth.uid()) AND user_id IS NULL)
  );

-- Also add admin policy for inserting with specific user_id
CREATE POLICY "Admins can insert STARW purchases for any user"
  ON public.starw_purchases
  FOR INSERT
  WITH CHECK (is_admin(auth.uid()));
