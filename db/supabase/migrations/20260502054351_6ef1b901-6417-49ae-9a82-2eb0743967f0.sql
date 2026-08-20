-- Column for the uploaded e-SIM file
ALTER TABLE public.str_dome_requests
  ADD COLUMN IF NOT EXISTS esim_file_path text;

-- Private bucket for e-SIM deliveries
INSERT INTO storage.buckets (id, name, public)
VALUES ('esim-deliveries', 'esim-deliveries', false)
ON CONFLICT (id) DO NOTHING;

-- Admins can upload / replace / delete e-SIM files in this bucket
CREATE POLICY "Admins manage esim deliveries"
  ON storage.objects FOR ALL
  USING (bucket_id = 'esim-deliveries' AND public.has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (bucket_id = 'esim-deliveries' AND public.has_role(auth.uid(), 'admin'::app_role));

-- Members can read their own e-SIM file (folder = user_id)
CREATE POLICY "Users read own esim deliveries"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'esim-deliveries'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );