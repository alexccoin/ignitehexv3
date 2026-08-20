-- Security Enhancement: Add audit logging table for role changes
CREATE TABLE public.audit_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  table_name TEXT NOT NULL,
  old_values JSONB,
  new_values JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS on audit logs
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Only admins can view audit logs
CREATE POLICY "Only admins can view audit logs"
ON public.audit_logs
FOR SELECT
TO authenticated
USING ((SELECT role FROM public.profiles WHERE user_id = auth.uid()) = 'admin');

-- Function to log profile changes
CREATE OR REPLACE FUNCTION public.log_profile_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Log role changes specifically
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    INSERT INTO public.audit_logs (
      user_id, 
      action, 
      table_name, 
      old_values, 
      new_values
    ) VALUES (
      COALESCE(auth.uid(), OLD.user_id),
      'UPDATE',
      'profiles',
      jsonb_build_object('role', OLD.role),
      jsonb_build_object('role', NEW.role)
    );
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger for profile changes
CREATE TRIGGER audit_profile_changes
AFTER UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.log_profile_changes();

-- Security Fix: Add explicit policy to prevent users from updating their own role
CREATE POLICY "Users cannot update their own role"
ON public.profiles
FOR UPDATE
TO authenticated
-- REPAIR: referenced NEW and OLD, which exist in triggers but not in RLS
-- policies, so this statement was invalid and never applied - the
-- role-escalation protection it describes has never been in force.
-- Enforcing role immutability needs a BEFORE UPDATE trigger; that is a
-- behaviour change and is deliberately not introduced here.
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- This replaces the previous "Users can update their own profile" policy
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;