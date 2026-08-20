-- Deduplicate user_profiles by user_id (keep most recently updated)
WITH ranked AS (
  SELECT id, user_id, created_at, updated_at,
         ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY updated_at DESC NULLS LAST, created_at DESC) rn
  FROM public.user_profiles
)
DELETE FROM public.user_profiles p
USING ranked r
WHERE p.id = r.id AND r.rn > 1;

-- Add UNIQUE constraint on user_id so ON CONFLICT (user_id) works
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_profiles_user_id_key'
      AND conrelid = 'public.user_profiles'::regclass
  ) THEN
    ALTER TABLE public.user_profiles
    ADD CONSTRAINT user_profiles_user_id_key UNIQUE (user_id);
  END IF;
END $$;
