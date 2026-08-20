-- Drop the restrictive INSERT policy
DROP POLICY IF EXISTS "Users can insert own security audit logs" ON security_audit_log;

-- Create a more permissive INSERT policy that allows:
-- 1. Authenticated users to log their own events (user_id = auth.uid())
-- 2. Unauthenticated logging for signup/login attempts (user_id IS NULL)
CREATE POLICY "Allow security audit log inserts" 
ON security_audit_log FOR INSERT 
WITH CHECK (
  user_id IS NULL OR user_id = auth.uid()
);