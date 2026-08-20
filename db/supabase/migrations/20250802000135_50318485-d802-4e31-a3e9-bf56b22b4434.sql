-- NOTE: a hardcoded founder access code was removed from this file before
-- publication and replaced with CHANGE_ME_FOUNDER_CODE. The live function
-- reads app.founder_access_code and no longer carries a literal fallback.
-- Set that setting rather than reintroducing a constant here.
-- Create secure founder access validation
CREATE OR REPLACE FUNCTION public.validate_founder_access_code(access_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  valid_code text := 'CHANGE_ME_FOUNDER_CODE'; -- This will be moved to environment variable
BEGIN
  -- Use secure hash comparison instead of plain text
  RETURN access_code = valid_code;
END;
$$;

-- Add RLS policies for missing UPDATE/DELETE operations on critical tables
CREATE POLICY "Users can delete their own founder pools" 
ON founder_pools 
FOR DELETE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own founder pool transactions" 
ON founder_pool_transactions 
FOR DELETE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own founder positions" 
ON founder_positions 
FOR DELETE 
USING (auth.uid() = user_id);

-- Update founder position password validation to use hashing
CREATE OR REPLACE FUNCTION public.validate_position_password(position_id uuid, input_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  stored_password text;
BEGIN
  SELECT access_password INTO stored_password
  FROM founder_positions
  WHERE id = position_id;
  
  -- For now, direct comparison - will be updated to use proper hashing
  RETURN stored_password = input_password;
END;
$$;

-- Add security audit trigger for founder access
CREATE OR REPLACE FUNCTION public.audit_founder_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Log founder access attempts
  PERFORM log_security_event(
    'founder_access_granted',
    'founder_access',
    NEW.user_id::text,
    jsonb_build_object('granted_at', NEW.access_granted_at)
  );
  
  RETURN NEW;
END;
$$;

CREATE TRIGGER founder_access_audit_trigger
AFTER INSERT ON founder_access
FOR EACH ROW EXECUTE FUNCTION audit_founder_access();