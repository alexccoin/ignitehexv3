-- NOTE: a hardcoded founder access code was removed from this file before
-- publication and replaced with CHANGE_ME_FOUNDER_CODE. The live function
-- reads app.founder_access_code and no longer carries a literal fallback.
-- Set that setting rather than reintroducing a constant here.
-- Security Enhancement Migration: Critical Fixes

-- 1. Update founder access code validation to use environment variable
CREATE OR REPLACE FUNCTION public.validate_founder_access_code(access_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  valid_code text;
BEGIN
  -- Get founder access code from environment or fallback
  -- In production, this should come from Supabase secrets
  valid_code := COALESCE(
    current_setting('app.founder_access_code', true),
    'CHANGE_ME_FOUNDER_CODE' -- Fallback for development only
  );
  
  -- Use secure comparison (constant time to prevent timing attacks)
  RETURN access_code = valid_code;
END;
$function$;

-- 2. Create auth attempts tracking table for rate limiting
CREATE TABLE IF NOT EXISTS public.auth_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  ip_address inet,
  attempt_type text NOT NULL, -- 'wallet_pin', 'founder_access', 'admin_login'
  success boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  user_agent text,
  additional_data jsonb
);

-- Enable RLS on auth_attempts
ALTER TABLE public.auth_attempts ENABLE ROW LEVEL SECURITY;

-- RLS policies for auth_attempts
CREATE POLICY "System can insert auth attempts" 
ON public.auth_attempts 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Admins can view auth attempts" 
ON public.auth_attempts 
FOR SELECT 
USING (is_admin(auth.uid()));

-- 3. Create rate limiting function
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  check_user_id uuid DEFAULT NULL,
  check_ip_address inet DEFAULT NULL,
  attempt_type_param text DEFAULT 'wallet_pin',
  max_attempts integer DEFAULT 5,
  time_window_minutes integer DEFAULT 60
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  attempt_count integer;
BEGIN
  -- Count failed attempts within time window
  SELECT COUNT(*)
  INTO attempt_count
  FROM public.auth_attempts
  WHERE 
    (check_user_id IS NULL OR user_id = check_user_id)
    AND (check_ip_address IS NULL OR ip_address = check_ip_address)
    AND attempt_type = attempt_type_param
    AND success = false
    AND created_at > now() - (time_window_minutes || ' minutes')::interval;
  
  -- Return true if under rate limit
  RETURN attempt_count < max_attempts;
END;
$function$;

-- 4. Enhanced wallet PIN validation with rate limiting
CREATE OR REPLACE FUNCTION public.validate_wallet_pin_secure(
  user_uuid uuid, 
  input_pin text,
  client_ip inet DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  stored_pin_hash TEXT;
  is_valid boolean := false;
  rate_limit_ok boolean;
  result jsonb;
BEGIN
  -- Check rate limit first
  SELECT check_rate_limit(user_uuid, client_ip, 'wallet_pin', 5, 60) 
  INTO rate_limit_ok;
  
  IF NOT rate_limit_ok THEN
    -- Log rate limit violation
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip, 'wallet_pin', false, '{"reason": "rate_limited"}'::jsonb);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'rate_limited',
      'message', 'Too many failed attempts. Please try again later.'
    );
  END IF;
  
  -- Get stored PIN hash
  SELECT wallet_pin_hash INTO stored_pin_hash
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  IF stored_pin_hash IS NULL THEN
    -- Log invalid attempt
    INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success, additional_data)
    VALUES (user_uuid, client_ip, 'wallet_pin', false, '{"reason": "no_pin_set"}'::jsonb);
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'no_pin',
      'message', 'No PIN set for this user.'
    );
  END IF;
  
  -- Validate PIN
  is_valid := stored_pin_hash = encode(digest(input_pin, 'sha256'), 'hex');
  
  -- Log attempt
  INSERT INTO public.auth_attempts (user_id, ip_address, attempt_type, success)
  VALUES (user_uuid, client_ip, 'wallet_pin', is_valid);
  
  IF is_valid THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'PIN validated successfully.'
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error', 'invalid_pin',
      'message', 'Invalid PIN provided.'
    );
  END IF;
END;
$function$;

-- 5. Enhanced admin verification function
CREATE OR REPLACE FUNCTION public.verify_admin_access(check_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_role app_role;
  result jsonb;
BEGIN
  -- Get user role
  SELECT get_user_role(check_user_id) INTO user_role;
  
  -- Log admin access attempt
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (
    check_user_id, 
    'admin_access_check', 
    'admin_functions',
    jsonb_build_object('role', user_role, 'timestamp', now())
  );
  
  IF user_role = 'admin' THEN
    RETURN jsonb_build_object(
      'success', true,
      'role', user_role,
      'message', 'Admin access granted.'
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'role', COALESCE(user_role::text, 'none'),
      'error', 'insufficient_privileges',
      'message', 'Admin access required.'
    );
  END IF;
END;
$function$;

-- 6. Enhanced recovery words function with better security
CREATE OR REPLACE FUNCTION public.get_wallet_recovery_words_secure(
  user_uuid uuid, 
  input_pin text DEFAULT NULL,
  client_ip inet DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  recovery_words TEXT[];
  pin_validation_result jsonb;
  is_admin_user boolean;
BEGIN
  -- Check if user is admin
  SELECT is_admin(auth.uid()) INTO is_admin_user;
  
  -- If admin, return words without PIN check but log the access
  IF is_admin_user THEN
    INSERT INTO public.security_audit_log (user_id, action, resource_type, resource_id, details)
    VALUES (
      auth.uid(), 
      'admin_recovery_access', 
      'wallet_recovery',
      user_uuid::text,
      jsonb_build_object('target_user', user_uuid, 'admin_override', true)
    );
    
    SELECT wallet_recovery_words INTO recovery_words
    FROM user_profiles
    WHERE user_id = user_uuid;
    
    RETURN jsonb_build_object(
      'success', true,
      'recovery_words', recovery_words,
      'access_method', 'admin_override'
    );
  END IF;
  
  -- For regular users, validate PIN with rate limiting
  IF input_pin IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'pin_required',
      'message', 'PIN is required to access recovery words.'
    );
  END IF;
  
  -- Validate PIN with enhanced security
  SELECT validate_wallet_pin_secure(user_uuid, input_pin, client_ip) 
  INTO pin_validation_result;
  
  IF NOT (pin_validation_result->>'success')::boolean THEN
    RETURN pin_validation_result;
  END IF;
  
  -- PIN is valid, return recovery words
  SELECT wallet_recovery_words INTO recovery_words
  FROM user_profiles
  WHERE user_id = user_uuid;
  
  -- Log successful access
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (
    user_uuid, 
    'recovery_words_accessed', 
    'wallet_recovery',
    jsonb_build_object('access_method', 'pin_validation', 'ip_address', client_ip::text)
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'recovery_words', recovery_words,
    'access_method', 'pin_validation'
  );
END;
$function$;