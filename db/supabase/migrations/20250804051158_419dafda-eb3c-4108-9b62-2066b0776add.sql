-- Update RLS policy for user_staking_pools to allow admins to view all pools
DROP POLICY IF EXISTS "Admins can view all staking pools" ON user_staking_pools;

CREATE POLICY "Admins can view all staking pools" ON user_staking_pools
FOR SELECT
USING (is_admin(auth.uid()));

-- Also allow admins to update any staking pools
DROP POLICY IF EXISTS "Admins can update all staking pools" ON user_staking_pools;

CREATE POLICY "Admins can update all staking pools" ON user_staking_pools
FOR UPDATE
USING (is_admin(auth.uid()));

-- Allow admins to insert staking pools for any user
DROP POLICY IF EXISTS "Admins can insert staking pools" ON user_staking_pools;

CREATE POLICY "Admins can insert staking pools" ON user_staking_pools
FOR INSERT
WITH CHECK (is_admin(auth.uid()));