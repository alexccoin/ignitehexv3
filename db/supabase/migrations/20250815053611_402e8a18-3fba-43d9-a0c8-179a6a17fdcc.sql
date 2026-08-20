-- Fix RLS policy conflict by dropping existing policies first
DROP POLICY IF EXISTS "Admins can view all rate limits" ON public.enhanced_rate_limits;
DROP POLICY IF EXISTS "System can insert rate limits" ON public.enhanced_rate_limits;
DROP POLICY IF EXISTS "System can update rate limits" ON public.enhanced_rate_limits;
DROP POLICY IF EXISTS "System can delete old rate limits" ON public.enhanced_rate_limits;

-- Enable RLS if not already enabled
ALTER TABLE public.enhanced_rate_limits ENABLE ROW LEVEL SECURITY;

-- Add corrected RLS policies for enhanced_rate_limits
CREATE POLICY "rate_limits_admin_select" ON public.enhanced_rate_limits
  FOR SELECT USING (is_admin(auth.uid()));

CREATE POLICY "rate_limits_system_insert" ON public.enhanced_rate_limits
  FOR INSERT WITH CHECK (true);

CREATE POLICY "rate_limits_system_update" ON public.enhanced_rate_limits
  FOR UPDATE USING (true);

CREATE POLICY "rate_limits_system_delete" ON public.enhanced_rate_limits
  FOR DELETE USING (true);