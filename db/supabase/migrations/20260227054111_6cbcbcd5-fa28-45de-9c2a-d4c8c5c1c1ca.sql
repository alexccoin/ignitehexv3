
-- Fix: Update policy should apply to authenticated users
DROP POLICY IF EXISTS "Users can accept their own invitation" ON public.guardian_invitations;
CREATE POLICY "Users can accept their own invitation"
ON public.guardian_invitations
FOR UPDATE
TO authenticated
USING (
  invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())::text
  AND status = 'pending'
)
WITH CHECK (
  accepted_by = auth.uid()
);

-- Also fix the SELECT policy for email matching to use authenticated role
DROP POLICY IF EXISTS "Users can view invitations for their email" ON public.guardian_invitations;
CREATE POLICY "Users can view invitations for their email"
ON public.guardian_invitations
FOR SELECT
TO authenticated
USING (
  invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())::text
);
