-- Add two-factor authentication support to user profiles
ALTER TABLE public.user_profiles 
ADD COLUMN IF NOT EXISTS two_factor_enabled boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS two_factor_secret text,
ADD COLUMN IF NOT EXISTS backup_codes text[],
ADD COLUMN IF NOT EXISTS device_fingerprints jsonb DEFAULT '[]'::jsonb;

-- Add session management table
CREATE TABLE IF NOT EXISTS public.user_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  session_token text NOT NULL,
  device_fingerprint text,
  ip_address inet,
  user_agent text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  last_activity timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  revoked_at timestamp with time zone,
  revoked_reason text
);

-- Add RLS policies for user sessions
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own sessions" ON public.user_sessions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own sessions" ON public.user_sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own sessions" ON public.user_sessions
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all sessions" ON public.user_sessions
  FOR SELECT USING (is_admin(auth.uid()));

-- Add enhanced rate limiting table
CREATE TABLE IF NOT EXISTS public.enhanced_rate_limits (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  identifier text NOT NULL, -- IP, user_id, or combination
  operation_type text NOT NULL,
  attempts integer NOT NULL DEFAULT 1,
  window_start timestamp with time zone NOT NULL DEFAULT now(),
  last_attempt timestamp with time zone NOT NULL DEFAULT now(),
  blocked_until timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON public.user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON public.user_sessions(user_id, is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_enhanced_rate_limits_identifier ON public.enhanced_rate_limits(identifier, operation_type);
CREATE INDEX IF NOT EXISTS idx_enhanced_rate_limits_window ON public.enhanced_rate_limits(window_start, operation_type);

-- Create function for session cleanup
CREATE OR REPLACE FUNCTION public.cleanup_expired_sessions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Mark expired sessions as inactive
  UPDATE public.user_sessions 
  SET is_active = false,
      revoked_at = now(),
      revoked_reason = 'expired'
  WHERE expires_at < now() 
    AND is_active = true;
  
  -- Delete old expired sessions (older than 30 days)
  DELETE FROM public.user_sessions 
  WHERE expires_at < now() - interval '30 days';
  
  -- Cleanup old rate limit entries (older than 24 hours)
  DELETE FROM public.enhanced_rate_limits 
  WHERE window_start < now() - interval '24 hours';
END;
$function$;

-- Create function for advanced rate limiting
CREATE OR REPLACE FUNCTION public.check_advanced_rate_limit(
  identifier_param text,
  operation_type_param text,
  max_attempts_param integer DEFAULT 5,
  window_minutes_param integer DEFAULT 15,
  progressive_delay_param boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  current_window_start timestamp with time zone;
  rate_limit_record public.enhanced_rate_limits%ROWTYPE;
  progressive_delays integer[] := ARRAY[1, 5, 15, 60, 300]; -- seconds
  required_delay integer := 0;
  result jsonb;
BEGIN
  -- Calculate current window start
  current_window_start := date_trunc('minute', now()) - 
    ((EXTRACT(minute FROM now())::integer % window_minutes_param) || ' minutes')::interval;
  
  -- Get or create rate limit record
  SELECT * INTO rate_limit_record
  FROM public.enhanced_rate_limits
  WHERE identifier = identifier_param 
    AND operation_type = operation_type_param
    AND window_start = current_window_start;
  
  IF NOT FOUND THEN
    -- Create new rate limit record
    INSERT INTO public.enhanced_rate_limits (
      identifier, operation_type, window_start, attempts, last_attempt
    ) VALUES (
      identifier_param, operation_type_param, current_window_start, 1, now()
    ) RETURNING * INTO rate_limit_record;
    
    RETURN jsonb_build_object(
      'allowed', true,
      'attempts', 1,
      'window_start', current_window_start,
      'max_attempts', max_attempts_param
    );
  END IF;
  
  -- Check if blocked
  IF rate_limit_record.blocked_until IS NOT NULL AND rate_limit_record.blocked_until > now() THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'temporarily_blocked',
      'blocked_until', rate_limit_record.blocked_until,
      'retry_after', EXTRACT(epoch FROM (rate_limit_record.blocked_until - now()))::integer
    );
  END IF;
  
  -- Check rate limit
  IF rate_limit_record.attempts >= max_attempts_param THEN
    -- Calculate progressive delay if enabled
    IF progressive_delay_param THEN
      required_delay := progressive_delays[
        LEAST(rate_limit_record.attempts - max_attempts_param + 1, 
              array_length(progressive_delays, 1))
      ];
      
      -- Update blocked_until
      UPDATE public.enhanced_rate_limits
      SET blocked_until = now() + (required_delay || ' seconds')::interval,
          last_attempt = now()
      WHERE id = rate_limit_record.id;
    END IF;
    
    RETURN jsonb_build_object(
      'allowed', false,
      'reason', 'rate_limited',
      'attempts', rate_limit_record.attempts,
      'max_attempts', max_attempts_param,
      'retry_after', required_delay,
      'window_start', current_window_start
    );
  END IF;
  
  -- Increment attempts
  UPDATE public.enhanced_rate_limits
  SET attempts = attempts + 1,
      last_attempt = now()
  WHERE id = rate_limit_record.id;
  
  RETURN jsonb_build_object(
    'allowed', true,
    'attempts', rate_limit_record.attempts + 1,
    'window_start', current_window_start,
    'max_attempts', max_attempts_param
  );
END;
$function$;

-- Create function for session validation
CREATE OR REPLACE FUNCTION public.validate_user_session(
  session_token_param text,
  device_fingerprint_param text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  session_record public.user_sessions%ROWTYPE;
  result jsonb;
BEGIN
  -- Get session record
  SELECT * INTO session_record
  FROM public.user_sessions
  WHERE session_token = session_token_param
    AND is_active = true
    AND expires_at > now();
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid', false,
      'reason', 'session_not_found_or_expired'
    );
  END IF;
  
  -- Check device fingerprint if provided
  IF device_fingerprint_param IS NOT NULL AND 
     session_record.device_fingerprint IS NOT NULL AND
     session_record.device_fingerprint != device_fingerprint_param THEN
    
    -- Log suspicious activity
    INSERT INTO public.security_audit_log (
      user_id, action, resource_type, details
    ) VALUES (
      session_record.user_id,
      'suspicious_device_fingerprint',
      'session_validation',
      jsonb_build_object(
        'session_id', session_record.id,
        'expected_fingerprint', session_record.device_fingerprint,
        'provided_fingerprint', device_fingerprint_param
      )
    );
    
    RETURN jsonb_build_object(
      'valid', false,
      'reason', 'device_fingerprint_mismatch'
    );
  END IF;
  
  -- Update last activity
  UPDATE public.user_sessions
  SET last_activity = now()
  WHERE id = session_record.id;
  
  RETURN jsonb_build_object(
    'valid', true,
    'user_id', session_record.user_id,
    'session_id', session_record.id,
    'expires_at', session_record.expires_at
  );
END;
$function$;

-- Add trigger for automatic session cleanup
CREATE OR REPLACE FUNCTION public.auto_cleanup_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Run cleanup every 100 operations (approximately)
  IF random() < 0.01 THEN
    PERFORM cleanup_expired_sessions();
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Create trigger for automatic cleanup
DROP TRIGGER IF EXISTS auto_cleanup_sessions_trigger ON public.user_sessions;
CREATE TRIGGER auto_cleanup_sessions_trigger
  AFTER INSERT OR UPDATE ON public.user_sessions
  FOR EACH ROW
  EXECUTE FUNCTION auto_cleanup_trigger();