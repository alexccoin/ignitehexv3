
-- Private bucket for full data exports
INSERT INTO storage.buckets (id, name, public)
VALUES ('data-exports', 'data-exports', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: admins only
CREATE POLICY "Admins can read data-exports"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'data-exports' AND public.is_admin(auth.uid()));

CREATE POLICY "Admins can write data-exports"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'data-exports' AND public.is_admin(auth.uid()));

CREATE POLICY "Admins can delete data-exports"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'data-exports' AND public.is_admin(auth.uid()));

-- Export history table
CREATE TABLE public.data_export_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requested_by uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending', -- pending | running | completed | failed
  format text NOT NULL DEFAULT 'csv+sql', -- csv+sql | csv | sql
  csv_zip_path text,
  sql_dump_path text,
  total_tables integer,
  total_rows bigint,
  total_bytes bigint,
  error_message text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.data_export_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins view export history"
  ON public.data_export_history FOR SELECT
  USING (public.is_admin(auth.uid()));

CREATE POLICY "Admins insert export history"
  ON public.data_export_history FOR INSERT
  WITH CHECK (public.is_admin(auth.uid()));

CREATE POLICY "Admins update export history"
  ON public.data_export_history FOR UPDATE
  USING (public.is_admin(auth.uid()));

CREATE INDEX idx_data_export_history_created_at ON public.data_export_history(created_at DESC);
