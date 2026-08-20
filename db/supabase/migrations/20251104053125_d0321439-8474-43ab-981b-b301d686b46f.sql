-- Create comprehensive error logging and reporting system

-- Create error logs table for all application errors
CREATE TABLE IF NOT EXISTS public.error_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  error_type TEXT NOT NULL, -- 'client_error', 'api_error', 'database_error', 'network_error'
  error_code TEXT,
  error_message TEXT NOT NULL,
  error_stack TEXT,
  component_name TEXT,
  action_attempted TEXT,
  context JSONB DEFAULT '{}',
  user_agent TEXT,
  device_info JSONB,
  resolved BOOLEAN DEFAULT false,
  resolved_by UUID REFERENCES auth.users(id),
  resolved_at TIMESTAMP WITH TIME ZONE,
  resolution_notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Create index for efficient querying
CREATE INDEX IF NOT EXISTS idx_error_logs_user_id ON public.error_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_error_logs_created_at ON public.error_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_error_logs_resolved ON public.error_logs(resolved) WHERE NOT resolved;
CREATE INDEX IF NOT EXISTS idx_error_logs_error_type ON public.error_logs(error_type);

-- Enable RLS
ALTER TABLE public.error_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for error_logs
CREATE POLICY "Users can insert their own error logs"
  ON public.error_logs FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

CREATE POLICY "Admins can view all error logs"
  ON public.error_logs FOR SELECT
  TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Admins can update error logs"
  ON public.error_logs FOR UPDATE
  TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Create function to notify admins of critical errors
CREATE OR REPLACE FUNCTION notify_admin_of_critical_error()
RETURNS TRIGGER AS $$
BEGIN
  -- Only notify for critical error types
  IF NEW.error_type IN ('database_error', 'api_error') THEN
    -- Insert notification for admins (using user_messages table)
    INSERT INTO public.user_messages (
      sender_id,
      recipient_id,
      subject,
      message,
      message_type,
      metadata
    )
    SELECT 
      NEW.user_id,
      ur.user_id,
      'CRITICAL_ERROR',
      'Critical error occurred: ' || NEW.error_message,
      'system',
      jsonb_build_object(
        'error_id', NEW.id,
        'error_type', NEW.error_type,
        'component', NEW.component_name,
        'action', NEW.action_attempted
      )
    FROM public.user_roles ur
    WHERE ur.role = 'admin'::app_role;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to notify admins
DROP TRIGGER IF EXISTS trigger_notify_admin_critical_error ON public.error_logs;
CREATE TRIGGER trigger_notify_admin_critical_error
  AFTER INSERT ON public.error_logs
  FOR EACH ROW
  EXECUTE FUNCTION notify_admin_of_critical_error();

-- Add comments for documentation
COMMENT ON TABLE public.error_logs IS 'Centralized error logging for all application errors with admin notifications';
COMMENT ON COLUMN public.error_logs.error_type IS 'Type of error: client_error, api_error, database_error, network_error';
COMMENT ON COLUMN public.error_logs.context IS 'Additional context about the error including request data, user actions, etc.';
COMMENT ON COLUMN public.error_logs.device_info IS 'Device and browser information for debugging';
