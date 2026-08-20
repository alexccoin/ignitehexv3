-- Grant pool access to the current user
INSERT INTO public.pool_access (user_id, granted_by, is_active, expires_at)
VALUES ('bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', 'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b', true, NULL)
ON CONFLICT (user_id) DO UPDATE SET 
  is_active = true,
  expires_at = NULL;