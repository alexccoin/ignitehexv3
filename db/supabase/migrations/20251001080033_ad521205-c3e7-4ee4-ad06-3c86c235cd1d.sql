-- Critical Security Fix: Protect VIP Customer Data
-- Issue: vip_users table and view exposing sensitive customer information

-- Step 1: Enable RLS on vip_users table if not already enabled
ALTER TABLE vip_users ENABLE ROW LEVEL SECURITY;

-- Step 2: Add admin-only policies for vip_users table
DROP POLICY IF EXISTS "Admins can view VIP users" ON vip_users;
CREATE POLICY "Admins can view VIP users"
ON vip_users
FOR SELECT
TO authenticated
USING (is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can manage VIP users" ON vip_users;
CREATE POLICY "Admins can manage VIP users"
ON vip_users
FOR ALL
TO authenticated
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Step 3: Drop the potentially insecure vip_users_detailed view
-- The secure function get_vip_users_detailed() already has admin checks
DROP VIEW IF EXISTS vip_users_detailed;

-- Step 4: Log the security fix
INSERT INTO security_audit_log (
  user_id,
  action,
  resource_type,
  details
) VALUES (
  auth.uid(),
  'critical_security_fix_vip_exposure',
  'vip_users',
  jsonb_build_object(
    'fix_type', 'RLS_policy_enforcement',
    'severity', 'critical',
    'tables_secured', 'vip_users',
    'views_removed', 'vip_users_detailed',
    'timestamp', now()
  )
);