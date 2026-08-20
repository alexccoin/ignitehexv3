-- Drop existing policies on vesting_tokens
DROP POLICY IF EXISTS "Users can view their own vesting tokens" ON public.vesting_tokens;
DROP POLICY IF EXISTS "Admins can view all vesting tokens" ON public.vesting_tokens;
DROP POLICY IF EXISTS "Admins can insert vesting tokens" ON public.vesting_tokens;
DROP POLICY IF EXISTS "Admins can update vesting tokens" ON public.vesting_tokens;

-- Users can view their own vesting tokens
CREATE POLICY "Users can view their own vesting tokens" 
ON public.vesting_tokens 
FOR SELECT 
USING (auth.uid() = user_id);

-- Admins can view all vesting tokens
CREATE POLICY "Admins can view all vesting tokens" 
ON public.vesting_tokens 
FOR SELECT 
USING (public.is_admin(auth.uid()));

-- Admins can insert vesting tokens
CREATE POLICY "Admins can insert vesting tokens" 
ON public.vesting_tokens 
FOR INSERT 
WITH CHECK (public.is_admin(auth.uid()));

-- Admins can update vesting tokens
CREATE POLICY "Admins can update vesting tokens" 
ON public.vesting_tokens 
FOR UPDATE 
USING (public.is_admin(auth.uid()));