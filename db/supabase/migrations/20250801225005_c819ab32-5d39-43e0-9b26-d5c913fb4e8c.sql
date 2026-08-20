-- Drop and recreate the pgcrypto extension in public schema
DROP EXTENSION IF EXISTS "pgcrypto";
CREATE EXTENSION "pgcrypto" WITH SCHEMA public;

-- Test that the function is now available
SELECT gen_random_bytes(16) AS test;