-- Fix personal_nodes policies
DROP POLICY IF EXISTS "Admins can manage all personal nodes" ON public.personal_nodes;
DROP POLICY IF EXISTS "Users can insert their own personal node" ON public.personal_nodes;
DROP POLICY IF EXISTS "Users can update their own personal node" ON public.personal_nodes;
DROP POLICY IF EXISTS "Users can view their own personal node" ON public.personal_nodes;

CREATE POLICY "Admins can manage all personal nodes"
ON public.personal_nodes
FOR ALL
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY "Users can view their own personal node"
ON public.personal_nodes
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own personal node"
ON public.personal_nodes
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own personal node"
ON public.personal_nodes
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Fix supernodes policies
DROP POLICY IF EXISTS "Admins can manage all supernodes" ON public.supernodes;
DROP POLICY IF EXISTS "Users can view their own supernodes" ON public.supernodes;

CREATE POLICY "Admins can manage all supernodes"
ON public.supernodes
FOR ALL
TO authenticated
USING (public.is_admin(auth.uid()))
WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY "Users can view their own supernodes"
ON public.supernodes
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);