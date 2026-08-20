-- Recreate missing profile for jennifer@sei-grenzenlos.de
INSERT INTO public.profiles (user_id, email, full_name, role, created_at, updated_at)
VALUES (
  'a1d8a383-2941-4e72-a428-ea5a59e58466',
  'jennifer@sei-grenzenlos.de',
  'Jennifer',
  'user',
  now(),
  now()
)
ON CONFLICT (user_id) DO NOTHING;