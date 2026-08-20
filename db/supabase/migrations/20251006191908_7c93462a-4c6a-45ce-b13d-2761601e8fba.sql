-- Create function to allow users to reset their own PIN
CREATE OR REPLACE FUNCTION public.reset_user_pin()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'not_authenticated',
      'message', 'User must be authenticated to reset PIN'
    );
  END IF;
  
  -- Clear the PIN hash
  UPDATE public.user_profiles
  SET 
    wallet_pin_hash = NULL,
    updated_at = now()
  WHERE user_id = current_user_id;
  
  -- Log the PIN reset
  INSERT INTO public.security_audit_log (user_id, action, resource_type, details)
  VALUES (
    current_user_id,
    'pin_reset',
    'wallet_security',
    jsonb_build_object(
      'timestamp', now(),
      'reason', 'user_initiated_reset'
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'PIN has been reset successfully. You can now set a new PIN.'
  );
END;
$$;