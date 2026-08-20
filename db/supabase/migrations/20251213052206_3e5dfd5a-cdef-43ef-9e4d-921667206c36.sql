-- Create table to store AI analysis jobs and results
CREATE TABLE public.support_ticket_analyses (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  ticket_count INTEGER NOT NULL DEFAULT 0,
  analysis_result TEXT,
  error_message TEXT,
  created_by UUID REFERENCES auth.users(id),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.support_ticket_analyses ENABLE ROW LEVEL SECURITY;

-- Admins can view and create analyses
CREATE POLICY "Admins can manage analyses" ON public.support_ticket_analyses
  FOR ALL USING (
    EXISTS (SELECT 1 FROM user_roles WHERE user_roles.user_id = auth.uid() AND user_roles.role = 'admin')
  );

-- Create index for faster queries
CREATE INDEX idx_support_analyses_status ON public.support_ticket_analyses(status);
CREATE INDEX idx_support_analyses_created_at ON public.support_ticket_analyses(created_at DESC);