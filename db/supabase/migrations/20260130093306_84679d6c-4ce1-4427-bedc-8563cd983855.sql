
-- Add DELETE policy for admins on user_staking_pools
CREATE POLICY "Admins can delete staking pools"
ON public.user_staking_pools
FOR DELETE
USING (is_admin(auth.uid()));

-- Also add DELETE policy for users on their own pools (for future use)
CREATE POLICY "Users can delete their own staking pools"
ON public.user_staking_pools
FOR DELETE
USING (auth.uid() = user_id);
