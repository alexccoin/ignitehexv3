CREATE POLICY "SAFE admins can view profiles for credit lookup"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (public.is_safe_admin(auth.uid()));