-- Drop existing policies on starw_nodes
DROP POLICY IF EXISTS "Admins can manage all STARW nodes" ON public.starw_nodes;
DROP POLICY IF EXISTS "Users can view their own STARW nodes" ON public.starw_nodes;

-- Recreate policies
CREATE POLICY "Admins can manage all STARW nodes"
ON public.starw_nodes
FOR ALL
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY "Users can view their own STARW nodes"
ON public.starw_nodes
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);