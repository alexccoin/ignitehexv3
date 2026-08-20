CREATE TABLE IF NOT EXISTS public.profile_change_otps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pending_change_id uuid NOT NULL REFERENCES public.pending_profile_changes(id) ON DELETE CASCADE,
  otp_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_profile_change_otps_user ON public.profile_change_otps(user_id, expires_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profile_change_otps TO authenticated;
GRANT ALL ON public.profile_change_otps TO service_role;
ALTER TABLE public.profile_change_otps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own_profile_change_otps_select" ON public.profile_change_otps
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "own_profile_change_otps_insert" ON public.profile_change_otps
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "own_profile_change_otps_delete" ON public.profile_change_otps
  FOR DELETE TO authenticated USING (user_id = auth.uid());