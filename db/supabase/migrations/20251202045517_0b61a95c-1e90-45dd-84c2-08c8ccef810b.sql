-- Create table for tracking background balance correction jobs
CREATE TABLE IF NOT EXISTS balance_correction_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID NOT NULL REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  total_users INTEGER NOT NULL DEFAULT 0,
  processed_count INTEGER NOT NULL DEFAULT 0,
  success_count INTEGER NOT NULL DEFAULT 0,
  fail_count INTEGER NOT NULL DEFAULT 0,
  progress_percentage INTEGER NOT NULL DEFAULT 0 CHECK (progress_percentage >= 0 AND progress_percentage <= 100),
  error_log TEXT[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  last_updated TIMESTAMPTZ DEFAULT now()
);

-- Add index for querying recent jobs
CREATE INDEX IF NOT EXISTS idx_balance_correction_jobs_created_by ON balance_correction_jobs(created_by);
CREATE INDEX IF NOT EXISTS idx_balance_correction_jobs_status ON balance_correction_jobs(status);
CREATE INDEX IF NOT EXISTS idx_balance_correction_jobs_created_at ON balance_correction_jobs(created_at DESC);

-- Enable RLS
ALTER TABLE balance_correction_jobs ENABLE ROW LEVEL SECURITY;

-- Admin can view all jobs
CREATE POLICY "Admins can view all balance correction jobs"
  ON balance_correction_jobs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_roles.user_id = auth.uid()
      AND user_roles.role = 'admin'
    )
  );

-- Service role can insert/update jobs (for edge function)
CREATE POLICY "Service role can manage balance correction jobs"
  ON balance_correction_jobs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE balance_correction_jobs IS 'Tracks background balance correction jobs that run independently of admin connection';