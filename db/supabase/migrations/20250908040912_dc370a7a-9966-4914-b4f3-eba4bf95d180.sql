-- Drop the old hash_pin_secure function that only takes input_pin
DROP FUNCTION IF EXISTS public.hash_pin_secure(input_pin text);

-- Ensure only our correct function exists
-- The function with (pin_text text, user_uuid uuid) should remain