-- Fix profile_changes RLS policies to use secure admin check function
-- and add foreign key to user_profiles for easier querying

-- Drop existing policies
DROP POLICY IF EXISTS "Admins can view all profile changes" ON public.profile_changes;
DROP POLICY IF EXISTS "Users can view their own profile changes" ON public.profile_changes;
DROP POLICY IF EXISTS "Users can insert their own profile changes" ON public.profile_changes;

-- Create updated policies using secure functions
CREATE POLICY "Admins view all profile changes secure"
ON public.profile_changes
FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "Users view own profile changes"
ON public.profile_changes
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "System can insert profile changes"
ON public.profile_changes
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Similarly fix pending_profile_changes policies
DROP POLICY IF EXISTS "Admins can view all pending changes" ON public.pending_profile_changes;
DROP POLICY IF EXISTS "Admins can update all pending changes" ON public.pending_profile_changes;

CREATE POLICY "Admins view all pending changes secure"
ON public.pending_profile_changes
FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins update all pending changes secure"
ON public.pending_profile_changes
FOR UPDATE
TO authenticated
USING (has_role(auth.uid(), 'admin'))
WITH CHECK (has_role(auth.uid(), 'admin'));

-- Add comment
COMMENT ON TABLE public.profile_changes IS 'Audit log of approved profile changes';
COMMENT ON TABLE public.pending_profile_changes IS 'Profile changes awaiting admin approval';