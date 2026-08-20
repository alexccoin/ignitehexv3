-- Tighten RLS for github_integrations to prevent cross-user access and enforce proper WITH CHECK

-- Ensure RLS is enabled (idempotent)
ALTER TABLE public.github_integrations ENABLE ROW LEVEL SECURITY;

-- Drop existing broad policy if present
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'github_integrations' 
      AND policyname = 'Users can manage own GitHub integration secure'
  ) THEN
    DROP POLICY "Users can manage own GitHub integration secure" ON public.github_integrations;
  END IF;
END$$;

-- Admins can manage all integrations
CREATE POLICY "Admins can manage all GitHub integrations"
ON public.github_integrations
FOR ALL
USING (is_admin(auth.uid()))
WITH CHECK (is_admin(auth.uid()));

-- Users can view their own integrations
CREATE POLICY "Users can view own GitHub integrations"
ON public.github_integrations
FOR SELECT
USING (auth.uid() = user_id);

-- Users can insert their own integrations
CREATE POLICY "Users can insert own GitHub integrations"
ON public.github_integrations
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can update their own integrations
CREATE POLICY "Users can update own GitHub integrations"
ON public.github_integrations
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Users can delete their own integrations
CREATE POLICY "Users can delete own GitHub integrations"
ON public.github_integrations
FOR DELETE
USING (auth.uid() = user_id);
