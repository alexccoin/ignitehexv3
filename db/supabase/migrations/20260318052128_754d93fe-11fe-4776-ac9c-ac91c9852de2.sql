-- Allow admins to insert audit logs for any user
CREATE POLICY "Admins can insert private seed str audit logs"
ON public.private_seed_str_audit_log
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'admin'::app_role
  )
);

-- Allow seed_str_admins to insert audit logs for any user
CREATE POLICY "seed_str_admins can insert private seed str audit logs"
ON public.private_seed_str_audit_log
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'seed_str_admin'::app_role
  )
);

-- Allow seed_str_admins to view audit logs
CREATE POLICY "seed_str_admins can view private seed str audit logs"
ON public.private_seed_str_audit_log
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_roles.user_id = auth.uid()
    AND user_roles.role = 'seed_str_admin'::app_role
  )
);

-- Ensure arss_transactions allows admin_credit transaction type for admins
DROP POLICY IF EXISTS "Admins can create correction transactions for any user" ON public.arss_transactions;
CREATE POLICY "Admins can create correction transactions for any user"
ON public.arss_transactions
FOR INSERT
TO authenticated
WITH CHECK (
  is_admin(auth.uid())
  AND transaction_type = ANY (ARRAY['voucher_correction', 'admin_correction', 'manual_credit', 'credit', 'balance_correction'])
);