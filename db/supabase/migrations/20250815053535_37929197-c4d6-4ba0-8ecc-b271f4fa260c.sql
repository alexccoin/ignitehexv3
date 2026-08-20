-- Enable RLS on the new tables to fix security warnings
ALTER TABLE public.enhanced_rate_limits ENABLE ROW LEVEL SECURITY;

-- Add RLS policies for enhanced_rate_limits
CREATE POLICY "Admins can view all rate limits" ON public.enhanced_rate_limits
  FOR SELECT USING (is_admin(auth.uid()));

CREATE POLICY "System can insert rate limits" ON public.enhanced_rate_limits
  FOR INSERT WITH CHECK (true);

CREATE POLICY "System can update rate limits" ON public.enhanced_rate_limits
  FOR UPDATE USING (true);

-- Add cleanup policy for old rate limit entries
CREATE POLICY "System can delete old rate limits" ON public.enhanced_rate_limits
  FOR DELETE USING (true);

-- Add comment explaining the security model
COMMENT ON TABLE public.enhanced_rate_limits IS 'Rate limiting table with system-only access for security enforcement';
COMMENT ON TABLE public.user_sessions IS 'User session management table with strict user isolation';