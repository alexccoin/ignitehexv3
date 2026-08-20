
-- Drop and recreate the UPDATE policy to be more permissive for auto-accept
DROP POLICY IF EXISTS "Users can accept their own invitation" ON guardian_invitations;

CREATE POLICY "Users can accept their own invitation"
ON guardian_invitations
FOR UPDATE
USING (
  invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  AND status = 'pending'
)
WITH CHECK (
  accepted_by = auth.uid()
);

-- Also ensure SELECT works for pending invitations
DROP POLICY IF EXISTS "Users can view invitations for their email" ON guardian_invitations;

CREATE POLICY "Users can view invitations for their email"
ON guardian_invitations
FOR SELECT
USING (
  invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
);
