
-- 1. Restrict guardian_flash_alerts SELECT to admins only
DROP POLICY IF EXISTS "Guardian users can view alerts" ON public.guardian_flash_alerts;
CREATE POLICY "Admins can view flash alerts"
  ON public.guardian_flash_alerts
  FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));

-- 2. Fix arx_voting_records voter self-read policy (voter_id references arx_club_members.id, not auth.uid())
DROP POLICY IF EXISTS "Voters can view their own voting records" ON public.arx_voting_records;
CREATE POLICY "Voters can view their own voting records"
  ON public.arx_voting_records
  FOR SELECT
  TO authenticated
  USING (
    voter_id IN (SELECT id FROM public.arx_club_members WHERE user_id = auth.uid())
  );

-- 3. Drop the plaintext github_integrations.access_token column (encrypted_access_token is the canonical store; current row count = 0)
ALTER TABLE public.github_integrations DROP COLUMN IF EXISTS access_token;
