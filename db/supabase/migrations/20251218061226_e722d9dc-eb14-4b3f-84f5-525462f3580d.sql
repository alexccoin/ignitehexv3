-- Reset the admin user's PIN to '123456' using a fresh bcrypt hash
-- This bypasses the (now-fixed) trigger to set a known working PIN
UPDATE public.user_profiles
SET wallet_pin_hash = crypt('123456', gen_salt('bf', 8)),
    updated_at = now()
WHERE user_id = 'bfb7c97b-7e1a-4de2-9d20-e71b3fd4655b';