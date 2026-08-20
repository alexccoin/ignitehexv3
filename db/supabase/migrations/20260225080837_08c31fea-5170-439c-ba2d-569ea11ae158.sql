-- Allow users to accept invitations that match their email
CREATE POLICY "Users can accept their own invitation"
ON public.guardian_invitations
FOR UPDATE
TO authenticated
USING (
  invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  AND status = 'pending'
)
WITH CHECK (
  accepted_by = auth.uid()
  AND status = 'accepted'
);

-- Allow users to read pending invitations matching their email
CREATE POLICY "Users can view invitations for their email"
ON public.guardian_invitations
FOR SELECT
TO authenticated
USING (
  invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
);

-- Allow users to insert their own wallets (for auto-creation on invitation acceptance)
CREATE POLICY "Users can create their own wallets"
ON public.guardian_wallets
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());