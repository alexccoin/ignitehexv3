-- Fix staking_data_cache table security: restrict to admin access only

-- Drop existing overly permissive policies
DROP POLICY IF EXISTS "Service role manages cache" ON public.staking_data_cache;
DROP POLICY IF EXISTS "Anyone can read cache" ON public.staking_data_cache;
DROP POLICY IF EXISTS "Public can read cache" ON public.staking_data_cache;

-- Create admin-only read policy
CREATE POLICY "Only admins can read staking cache"
ON public.staking_data_cache
FOR SELECT
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

-- Create admin-only insert policy
CREATE POLICY "Only admins can insert staking cache"
ON public.staking_data_cache
FOR INSERT
TO authenticated
WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Create admin-only update policy
CREATE POLICY "Only admins can update staking cache"
ON public.staking_data_cache
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- Create admin-only delete policy
CREATE POLICY "Only admins can delete staking cache"
ON public.staking_data_cache
FOR DELETE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'));