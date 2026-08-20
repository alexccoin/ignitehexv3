-- Allow seed_str_admin role to manage user_str_shares (INSERT, UPDATE, SELECT)

-- UPDATE policy for seed_str_admin
CREATE POLICY "seed_str_admins can update str shares"
ON public.user_str_shares
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'seed_str_admin'::app_role
  )
);

-- INSERT policy for seed_str_admin
CREATE POLICY "seed_str_admins can insert str shares"
ON public.user_str_shares
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'seed_str_admin'::app_role
  )
);

-- SELECT policy for seed_str_admin (required to read before update)
CREATE POLICY "seed_str_admins can view all str shares"
ON public.user_str_shares
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'seed_str_admin'::app_role
  )
);