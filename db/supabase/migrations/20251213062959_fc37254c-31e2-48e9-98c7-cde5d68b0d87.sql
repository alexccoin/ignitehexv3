-- Create table to track bulk support ticket fix jobs
CREATE TABLE IF NOT EXISTS public.support_ticket_fix_jobs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  total_items INTEGER NOT NULL DEFAULT 0,
  processed_count INTEGER NOT NULL DEFAULT 0,
  success_count INTEGER NOT NULL DEFAULT 0,
  fail_count INTEGER NOT NULL DEFAULT 0,
  progress_percentage INTEGER NOT NULL DEFAULT 0,
  error_log TEXT[] DEFAULT ARRAY[]::TEXT[],
  results JSONB,
  last_updated TIMESTAMPTZ
);

-- Enable RLS
ALTER TABLE public.support_ticket_fix_jobs ENABLE ROW LEVEL SECURITY;

-- Admin access policy
CREATE POLICY "Admins can manage support ticket fix jobs"
ON public.support_ticket_fix_jobs
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = auth.uid() 
    AND user_roles.role = 'admin'
  )
);

-- Create index for efficient querying
CREATE INDEX idx_support_ticket_fix_jobs_status ON public.support_ticket_fix_jobs(status);
CREATE INDEX idx_support_ticket_fix_jobs_created_by ON public.support_ticket_fix_jobs(created_by);