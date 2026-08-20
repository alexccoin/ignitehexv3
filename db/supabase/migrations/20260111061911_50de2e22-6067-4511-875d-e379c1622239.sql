-- Fix security_audit_log to allow edge functions (anon role) to insert
DROP POLICY IF EXISTS "Authenticated can insert audit logs" ON public.security_audit_log;

CREATE POLICY "System can insert audit logs"
ON public.security_audit_log FOR INSERT
TO anon, authenticated
WITH CHECK (true);