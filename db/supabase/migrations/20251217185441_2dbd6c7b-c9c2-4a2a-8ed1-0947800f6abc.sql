-- Normalize all str_domain_username values by removing STR./str. prefix if present
-- This is a non-destructive operation that only cleans up the format

UPDATE user_profiles
SET str_domain_username = REGEXP_REPLACE(str_domain_username, '^(STR\.|str\.)', '', 'i'),
    updated_at = now()
WHERE str_domain_username ~ '^(STR\.|str\.)';