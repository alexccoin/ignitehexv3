-- Create security-focused user profile update function
CREATE OR REPLACE FUNCTION public.secure_update_user_profile(
  profile_data JSONB
) RETURNS BOOLEAN AS $$
DECLARE
  current_user_id UUID;
BEGIN
  -- Get current authenticated user
  current_user_id := auth.uid();
  
  -- Ensure user is authenticated
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  
  -- Validate input data (basic sanitization)
  IF profile_data IS NULL OR jsonb_typeof(profile_data) != 'object' THEN
    RAISE EXCEPTION 'Invalid profile data format';
  END IF;
  
  -- Only allow updating own profile unless admin
  IF NOT is_admin(current_user_id) THEN
    IF profile_data->>'user_id' IS NOT NULL AND 
       (profile_data->>'user_id')::UUID != current_user_id THEN
      RAISE EXCEPTION 'Cannot update other users profile';
    END IF;
  END IF;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add audit logging table for sensitive operations
CREATE TABLE IF NOT EXISTS public.security_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id TEXT,
  details JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on audit log
ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;

-- Only admins can view audit logs
CREATE POLICY "Admins can view audit logs" ON public.security_audit_log
FOR SELECT USING (is_admin(auth.uid()));

-- Function to log security events
CREATE OR REPLACE FUNCTION public.log_security_event(
  action_name TEXT,
  resource_type_name TEXT,
  resource_id_val TEXT DEFAULT NULL,
  details_json JSONB DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.security_audit_log (
    user_id, action, resource_type, resource_id, details
  ) VALUES (
    auth.uid(), action_name, resource_type_name, resource_id_val, details_json
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add input validation function for founder positions
CREATE OR REPLACE FUNCTION public.validate_founder_position_input(
  input_data JSONB
) RETURNS BOOLEAN AS $$
BEGIN
  -- Validate required fields
  IF input_data->>'user_id' IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;
  
  -- Validate BTC amounts are positive
  IF (input_data->>'input_btc_amount')::NUMERIC <= 0 THEN
    RAISE EXCEPTION 'Input BTC amount must be positive';
  END IF;
  
  -- Validate USD values are reasonable
  IF (input_data->>'current_usd_value')::NUMERIC <= 0 OR 
     (input_data->>'current_usd_value')::NUMERIC > 10000000 THEN
    RAISE EXCEPTION 'USD value out of reasonable range';
  END IF;
  
  -- Log the validation attempt
  PERFORM log_security_event('validate_founder_position', 'founder_positions', input_data->>'user_id');
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;