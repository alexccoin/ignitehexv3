-- Drop existing policies for seed_str_applications
DROP POLICY IF EXISTS "Admins can view all seed applications" ON public.seed_str_applications;
DROP POLICY IF EXISTS "Admins can update seed applications" ON public.seed_str_applications;

-- Create new policies that include seed_str_admin role
CREATE POLICY "Admins and seed_str_admins can view all seed applications"
ON public.seed_str_applications
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('admin', 'seed_str_admin')
  )
  OR auth.uid() = user_id
);

CREATE POLICY "Admins and seed_str_admins can update seed applications"
ON public.seed_str_applications
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('admin', 'seed_str_admin')
  )
);

-- Drop existing policy for seed_str_audit_log
DROP POLICY IF EXISTS "Admins can view seed audit logs" ON public.seed_str_audit_log;

-- Create new policy that includes seed_str_admin role
CREATE POLICY "Admins and seed_str_admins can view seed audit logs"
ON public.seed_str_audit_log
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role IN ('admin', 'seed_str_admin')
  )
);