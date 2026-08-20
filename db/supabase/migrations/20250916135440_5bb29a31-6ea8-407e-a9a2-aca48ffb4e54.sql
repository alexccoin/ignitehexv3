-- Create a temporary function to self-assign admin role (should be removed after use)
CREATE OR REPLACE FUNCTION public.emergency_assign_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
BEGIN
  -- Get current authenticated user
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Must be authenticated to use this function';
  END IF;
  
  -- Insert admin role for current user
  INSERT INTO user_roles (user_id, role)
  VALUES (current_user_id, 'admin'::app_role)
  ON CONFLICT (user_id, role) DO NOTHING;
  
  -- Log the emergency admin assignment
  INSERT INTO security_audit_log (
    user_id, action, resource_type, details
  ) VALUES (
    current_user_id, 
    'emergency_admin_assignment', 
    'user_roles',
    jsonb_build_object('timestamp', now(), 'note', 'Emergency admin access granted')
  );
  
  RETURN true;
END;
$$;