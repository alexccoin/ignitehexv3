-- Allow users to view their own login history (auth_attempts)
-- Enables the new Account Security page to list IPs and timestamps securely

-- Ensure RLS is enabled on auth_attempts (idempotent)
ALTER TABLE public.auth_attempts ENABLE ROW LEVEL SECURITY;

-- Create SELECT policy for users to view their own attempts
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'auth_attempts' 
      AND policyname = 'Users can view their own auth attempts'
  ) THEN
    CREATE POLICY "Users can view their own auth attempts"
    ON public.auth_attempts
    FOR SELECT
    USING (auth.uid() = user_id);
  END IF;
END$$;

-- Optional but helpful: index for fast queries by user and date
CREATE INDEX IF NOT EXISTS idx_auth_attempts_user_created 
  ON public.auth_attempts (user_id, created_at DESC);
